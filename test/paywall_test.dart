import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pawsitive_sync/core/logging/app_log.dart';
import 'package:pawsitive_sync/core/routing/app_router.dart';
import 'package:pawsitive_sync/core/routing/routes.dart';
import 'package:pawsitive_sync/core/theme/app_theme.dart';
import 'package:pawsitive_sync/data/care_repository.dart';
import 'package:pawsitive_sync/data/revenue_cat_service.dart';
import 'package:pawsitive_sync/domain/models.dart';
import 'package:pawsitive_sync/domain/paywall_reason.dart';
import 'package:pawsitive_sync/ui/meds/medicine_forms.dart';
import 'package:pawsitive_sync/ui/onboarding/onboarding_view_model.dart';
import 'package:provider/provider.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_log_helpers.dart';

import 'support/app_fonts.dart';

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
    await loadAppFonts();
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
    // The billed yearly amount leads; the monthly breakdown is secondary.
    expect(find.text('\$29.99/yr'), findsOneWidget);
    expect(find.text('\$2.49/mo · whole household'), findsOneWidget);
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

  group('trial timeline', () {
    testWidgets('a 7-day trial shows today, the reminder day and billing', (
      tester,
    ) async {
      await pumpPaywall(tester);
      await tester.scrollUntilVisible(
        find.text('How your free trial works'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Today'), findsOneWidget);
      expect(find.text('Oct 8'), findsOneWidget);
      expect(find.text('Oct 10'), findsOneWidget);
      expect(find.text(r'$29.99 per year starts'), findsOneWidget);
      expect(find.textContaining('whole household'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('no trial: no timeline, never a promise we can’t keep', (
      tester,
    ) async {
      final care = await pumpPaywall(tester);
      await care.setPlan(BillingPlan.monthly);
      await tester.pumpAndSettle();
      expect(find.text('How your free trial works'), findsNothing);
    });

    testWidgets('a 2-day trial drops the reminder line', (tester) async {
      RevenueCatService.debugOffer = PaywallOffer(
        offeringId: 'default',
        packages: const [],
        yearly: PlanOffer(
          package: storeOffer.yearly!.package,
          priceString: r'$29.99',
          price: 29.99,
          perMonthString: r'$2.49',
          trialDays: 2,
        ),
        monthly: storeOffer.monthly,
      );
      await pumpPaywall(tester);
      await tester.scrollUntilVisible(
        find.text('How your free trial works'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('We remind you'), findsNothing);
      expect(find.text('Oct 5'), findsOneWidget);
    });

    for (final dark in [false, true]) {
      testWidgets('timeline fits a small phone at 2x text, dark=$dark', (
        tester,
      ) async {
        await pumpPaywall(
          tester,
          size: const Size(320, 640),
          scale: 2,
          dark: dark,
        );
        await tester.scrollUntilVisible(
          find.text('How your free trial works'),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('first dose answered during setup', () {
    Future<CareRepository> finishSetup(
      WidgetTester tester, {
      required bool? given,
      bool hasMedicine = true,
    }) async {
      await loadAppFonts();
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final care = CareRepository(clock: () => DateTime(2026, 10, 3, 7));
      final model = OnboardingViewModel()
        ..setName('Milo')
        ..setSpecies(Species.dog)
        ..setForm(MedicineForm.tablet);
      model
        ..medName = 'Apoquel'
        ..medAmount = '1'
        ..hasMedicine = hasMedicine
        ..householdDone = true
        ..remindersAnswered = true
        ..firstDoseGiven = given;
      final router = createRouter(model);
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: model),
            ChangeNotifierProvider.value(value: care),
          ],
          child: MaterialApp.router(
            theme: AppTheme.light(),
            routerConfig: router,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: true),
              child: child!,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      router.go(AppRoutes.paywall);
      await tester.pumpAndSettle();
      final free = find.text('Continue free with 1 pet');
      await tester.ensureVisible(free);
      await tester.pumpAndSettle();
      await tester.tap(free);
      await tester.pumpAndSettle();
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        router.dispose();
        model.dispose();
        care.dispose();
      });
      return care;
    }

    testWidgets('"Yes, already given" logs today\'s dose (even before 8 AM)', (
      tester,
    ) async {
      final care = await finishSetup(tester, given: true);
      final med = care.medications.single;
      expect(
        care.loggedDose('${med.id}.morning', '2026-10-03')?.outcome,
        LogOutcome.given,
      );
      expectLogged('dose.log.completed', fields: {'offline': true});
      expectLogged('onboarding.first_dose_logged', fields: {'part': 'morning'});
    });

    testWidgets('"Not yet" and unanswered log no dose', (tester) async {
      for (final given in [false, null]) {
        AppLog.testRecords.clear();
        final care = await finishSetup(tester, given: given);
        expect(care.medications, hasLength(1));
        expect(care.logs, isEmpty);
        expectNotLogged('dose.log.completed');
        expectNotLogged('onboarding.first_dose_logged');
      }
    });

    testWidgets('no medicine: nothing to log, setup still finishes', (
      tester,
    ) async {
      final care = await finishSetup(tester, given: true, hasMedicine: false);
      expect(care.pets.single.name, 'Milo');
      expect(care.logs, isEmpty);
      expectNotLogged('onboarding.first_dose_logged');
    });
  });
}
