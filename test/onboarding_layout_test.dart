import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pawsitive_sync/core/layout/adaptive.dart';
import 'package:pawsitive_sync/core/routing/app_router.dart';
import 'package:pawsitive_sync/core/theme/app_theme.dart';
import 'package:pawsitive_sync/core/widgets/paws_widgets.dart';
import 'package:pawsitive_sync/data/care_repository.dart';
import 'package:pawsitive_sync/domain/models.dart';
import 'package:pawsitive_sync/ui/onboarding/caregivers_screen.dart';
import 'package:pawsitive_sync/ui/onboarding/conditions_screen.dart';
import 'package:pawsitive_sync/ui/onboarding/notifications_screen.dart';
import 'package:pawsitive_sync/ui/onboarding/onboarding_view_model.dart';
import 'package:pawsitive_sync/ui/onboarding/pet_basics_screen.dart';
import 'package:pawsitive_sync/ui/onboarding/pet_details_screen.dart';
import 'package:pawsitive_sync/ui/onboarding/welcome_screen.dart';
import 'package:pawsitive_sync/ui/paywall/paywall_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
    'redesigned setup preserves answers and completes the five steps',
    (tester) async {
      final model = OnboardingViewModel();
      final care = CareRepository();
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
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Get started'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), 'Miso');
      await tester.ensureVisible(find.text('Dog'));
      await tester.tap(find.text('Dog'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField), '4.6.1');
      await tester.pump();
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      await tester.enterText(find.byType(TextFormField), '4.6');
      await tester.pump();
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(model.petName, 'Miso');
      expect(model.species, Species.dog);
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(model.weight, '4.6');
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Diabetes'));
      await tester.tap(find.text('Diabetes'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue with 1 selected'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Partner or family'));
      await tester.tap(find.text('Partner or family'));
      await tester.pumpAndSettle();
      expect(model.caregivers, {'Partner or family'});
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Not now'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(find.byType(PaywallScreen), findsOneWidget);
      expect(model.remindersOn, isFalse);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      router.dispose();
      model.dispose();
      care.dispose();
    },
  );

  const screens = <Widget>[
    WelcomeScreen(),
    PetBasicsScreen(),
    PetDetailsScreen(),
    ConditionsScreen(),
    CaregiversScreen(),
    NotificationsScreen(),
  ];

  for (final scenario in [
    (size: const Size(390, 844), scale: 1.0, dark: false),
    (size: const Size(320, 568), scale: 2.0, dark: false),
    (size: const Size(390, 844), scale: 1.0, dark: true),
    (size: const Size(1024, 1366), scale: 1.0, dark: false),
  ]) {
    testWidgets('onboarding fits $scenario with reachable full-width actions', (
      tester,
    ) async {
      tester.view.physicalSize = scenario.size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final model = OnboardingViewModel()
        ..setName('Miso')
        ..toggleCondition('Diabetes')
        ..ensureDefaultCaregiver();
      addTearDown(model.dispose);

      for (final screen in screens) {
        await tester.pumpWidget(
          ChangeNotifierProvider.value(
            value: model,
            child: MaterialApp(
              theme: scenario.dark ? AppTheme.dark() : AppTheme.light(),
              home: MediaQuery(
                data: MediaQueryData(
                  size: scenario.size,
                  textScaler: TextScaler.linear(scenario.scale),
                  disableAnimations: true,
                ),
                child: AdaptivePage(child: screen),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: '$screen at $scenario');
        final action = find.byType(FilledButton).first;
        final rect = tester.getRect(action);
        final footer = tester.getRect(find.byType(OnboardingFooter));
        expect(rect.width, closeTo(footer.width - 48, 0.1));
        expect(rect.bottom, lessThanOrEqualTo(scenario.size.height));
        expect(action.hitTestable(), findsOneWidget);
        await tester.pumpWidget(const SizedBox.shrink());
      }
    });
  }

  testWidgets('keyboard leaves the name field and continue action reachable', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final model = OnboardingViewModel();
    addTearDown(model.dispose);
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: model,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const MediaQuery(
            data: MediaQueryData(
              size: Size(390, 844),
              viewInsets: EdgeInsets.only(bottom: 300),
            ),
            child: PetBasicsScreen(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), 'Miso');
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(
      tester.getRect(find.byType(FilledButton)).bottom,
      lessThanOrEqualTo(544),
    );
    expect(find.text('Continue').hitTestable(), findsOneWidget);
  });
}
