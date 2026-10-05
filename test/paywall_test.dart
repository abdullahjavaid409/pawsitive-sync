import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pawsitive_sync/core/logging/app_log.dart';
import 'package:pawsitive_sync/core/routing/app_router.dart';
import 'package:pawsitive_sync/core/routing/routes.dart';
import 'package:pawsitive_sync/core/theme/app_theme.dart';
import 'package:pawsitive_sync/data/care_repository.dart';
import 'package:pawsitive_sync/data/revenue_cat_service.dart';
import 'package:pawsitive_sync/domain/models.dart';
import 'package:pawsitive_sync/domain/paywall_reason.dart';
import 'package:pawsitive_sync/ui/onboarding/onboarding_view_model.dart';
import 'package:provider/provider.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_log_helpers.dart';

/// Every paywall moment, on small and large phones, light and dark, with
/// large text: no overflow, honest trial copy, Apple 3.1.2 essentials present.
void main() {
  // What RevenueCat returns for the default offering: the paywall shows only
  // these prices and trials, never its own.
  Package package(String id, PackageType type, double price, String label) =>
      Package(
        id,
        type,
        StoreProduct(id, '', '', price, label, 'USD'),
        const PresentedOfferingContext('default', null, null),
      );
  final storeOffer = PaywallOffer(
    offeringId: 'default',
    packages: const [],
    yearly: PlanOffer(
      package: package(r'$rc_annual', PackageType.annual, 29.99, r'$29.99'),
      priceString: r'$29.99',
      price: 29.99,
      perMonthString: r'$2.49',
      trialDays: 7,
    ),
    monthly: PlanOffer(
      package: package(r'$rc_monthly', PackageType.monthly, 4.99, r'$4.99'),
      priceString: r'$4.99',
      price: 4.99,
    ),
  );

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppLog.enableTestCapture();
    RevenueCatService.debugOffer = storeOffer;
  });
  tearDown(() {
    AppLog.disableTestCapture();
    RevenueCatService.debugOffer = null;
  });

  Future<CareRepository> pumpPaywall(
    WidgetTester tester, {
    PaywallReason? reason,
    Size size = const Size(390, 844),
    double scale = 1,
    bool dark = false,
  }) async {
    final font = FontLoader('Geist');
    for (final weight in ['Regular', 'Medium', 'SemiBold']) {
      font.addFont(rootBundle.load('assets/fonts/Geist-$weight.ttf'));
    }
    await font.load();
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final care = CareRepository(clock: () => DateTime(2026, 10, 3, 14));
    await care.addPet(name: 'Milo', species: Species.cat);
    final model = OnboardingViewModel()..isComplete = true;
    final router = createRouter(model);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: model),
          ChangeNotifierProvider.value(value: care),
        ],
        child: MaterialApp.router(
          theme: dark ? AppTheme.dark() : AppTheme.light(),
          routerConfig: router,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(scale),
              disableAnimations: true,
            ),
            child: child!,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    router.go(AppRoutes.paywallWith(reason: reason?.queryValue));
    await tester.pumpAndSettle();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      router.dispose();
      model.dispose();
      care.dispose();
    });
    return care;
  }

  void expectEssentials() {
    expect(find.text('Restore'), findsOneWidget);
    expect(find.text('Terms'), findsOneWidget);
    expect(find.text('Privacy'), findsOneWidget);
    expect(find.textContaining('Auto-renews'), findsOneWidget);
    expect(find.byTooltip('Close'), findsOneWidget);
    expectLogged(
      'billing.paywall.offer_shown',
      fields: {'offering': 'default'},
    );
  }

  for (final reason in PaywallReason.values) {
    testWidgets('${reason.name}: contextual headline + essentials', (
      tester,
    ) async {
      await pumpPaywall(tester, reason: reason);
      expect(find.text(reason.copy.$1), findsOneWidget);
      expectEssentials();
      expect(find.text('Start 7-day free trial · Yearly'), findsOneWidget);
      expect(tester.takeException(), isNull);
      expectLogged(
        'billing.paywall.opened',
        fields: {'reason': reason.queryValue},
      );
    });
  }

  testWidgets('monthly never promises a trial', (tester) async {
    await pumpPaywall(tester, reason: PaywallReason.secondPet);
    await tester.tap(find.text('Monthly'));
    await tester.pumpAndSettle();
    expect(find.text('Subscribe · \$4.99/month'), findsOneWidget);
    expect(find.textContaining('free trial'), findsNothing);
    expect(find.textContaining('\$4.99/month. Auto-renews'), findsOneWidget);
    await tester.tap(find.text('Yearly'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('7-day free trial, then \$29.99/year'),
      findsOneWidget,
    );
  });

  testWidgets('real savings badge shown on yearly', (tester) async {
    await pumpPaywall(tester);
    expect(find.text('Save 49%'), findsOneWidget);
    expect(find.text('\$2.49/mo'), findsOneWidget);
  });

  testWidgets('no RevenueCat offer: no made-up prices or trials', (
    tester,
  ) async {
    RevenueCatService.debugOffer = null;
    await pumpPaywall(tester);
    expect(find.textContaining('free trial'), findsNothing);
    expect(find.textContaining(r'$'), findsNothing);
    expect(find.text('Try again'), findsOneWidget);
    expectLogged('billing.paywall.offer_unavailable');
  });

  testWidgets('close dismisses an upgrade paywall', (tester) async {
    await pumpPaywall(tester, reason: PaywallReason.invite);
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expectLogged('billing.paywall.dismissed', fields: {'reason': 'invite'});
  });

  final layouts = {
    'iPhone SE': (const Size(375, 667), 1.0, false),
    'iPhone SE large text': (const Size(375, 667), 1.35, false),
    'Pro Max dark': (const Size(440, 956), 1.0, true),
    'small large text dark': (const Size(360, 640), 1.3, true),
  };
  for (final MapEntry(key: name, value: (size, scale, dark))
      in layouts.entries) {
    for (final reason in PaywallReason.values) {
      testWidgets('$name / ${reason.name}: no overflow', (tester) async {
        await pumpPaywall(
          tester,
          reason: reason,
          size: size,
          scale: scale,
          dark: dark,
        );
        expect(tester.takeException(), isNull);
        expect(find.textContaining('Start 7-day free trial'), findsOneWidget);
      });
    }
  }
}
