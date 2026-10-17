import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pawsitive_sync/core/layout/adaptive.dart';
import 'package:pawsitive_sync/core/routing/app_router.dart';
import 'package:pawsitive_sync/core/theme/app_theme.dart';
import 'package:pawsitive_sync/core/widgets/paws_widgets.dart';
import 'package:pawsitive_sync/data/care_repository.dart';
import 'package:pawsitive_sync/ui/onboarding/caregivers_screen.dart';
import 'package:pawsitive_sync/ui/onboarding/first_medicine_screen.dart';
import 'package:pawsitive_sync/ui/onboarding/notifications_screen.dart';
import 'package:pawsitive_sync/ui/onboarding/onboarding_view_model.dart';
import 'package:pawsitive_sync/ui/onboarding/pet_basics_screen.dart';
import 'package:pawsitive_sync/ui/onboarding/ready_screen.dart';
import 'package:pawsitive_sync/ui/onboarding/welcome_screen.dart';
import 'package:pawsitive_sync/ui/paywall/paywall_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
    'v14 setup: pet, first medicine, household, notifications, ready',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
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

      // 1. Pet: Continue waits for a name and says so.
      expect(find.text('Add your pet’s name to continue'), findsOneWidget);
      await tester.enterText(find.byType(TextFormField), 'Miso');
      await tester.tap(find.text('Dog'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      // 2. First medicine: name, form, amount; Free shows Pro on evening.
      expect(find.text('What does Miso take?'), findsOneWidget);
      // Nothing picked or red on arrival: no form, no frequency, no hint.
      expect(find.textContaining('Still needed'), findsNothing);
      expect(find.text('Amount per dose'), findsNothing);
      await tester.ensureVisible(find.text('Continue'));
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(model.hasMedicine, isFalse);
      // Everything missing at once, each under its own field.
      expect(find.text('Still needed: name · form'), findsOneWidget);
      expect(
        find.text('Add the medicine’s name, or skip this step'),
        findsOneWidget,
      );
      expect(find.text('Pick the form it comes in'), findsOneWidget);
      expect(find.text('Pick how often'), findsNothing);
      // Typing clears that field's message straight away.
      await tester.enterText(find.byType(TextField).first, 'Insulin');
      await tester.pump();
      expect(
        find.text('Add the medicine’s name, or skip this step'),
        findsNothing,
      );
      await tester.tap(find.text('Injection'));
      await tester.pumpAndSettle();
      expect(find.text('Pick the form it comes in'), findsNothing);
      expect(find.text('Amount per dose'), findsOneWidget);
      await tester.ensureVisible(find.text('Every day'));
      await tester.tap(find.text('Every day'));
      await tester.pump();
      expect(find.text('Pick how often'), findsNothing);
      expect(find.text('Add how much Miso gets each time.'), findsOneWidget);
      // + fills the amount without typing; − steps it back down.
      await tester.ensureVisible(find.bySemanticsLabel('More').first);
      await tester.tap(find.bySemanticsLabel('More').first);
      await tester.pump();
      expect(find.text('Add how much Miso gets each time.'), findsNothing);
      await tester.enterText(find.byType(TextField).at(1), '2');
      await tester.pump();
      expect(find.text('Pro'), findsNWidgets(2), reason: 'midday, evening');
      await tester.ensureVisible(find.text('Continue'));
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(model.hasMedicine, isTrue);
      expect(model.medAmountText, '2 units');

      // 3. Household: an address waits for after setup.
      await tester.enterText(find.byType(TextField), 'sara@');
      await tester.tap(find.text('Add'));
      await tester.pump();
      expect(
        find.text('Enter a full email, like sara@example.com'),
        findsOneWidget,
      );
      await tester.enterText(find.byType(TextField), 'sara@example.com');
      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(model.invites, ['sara@example.com']);
      expect(model.inviteAfterSetup, isTrue);

      // 4. Notifications: Not now.
      await tester.tap(find.text('Not now'));
      await tester.pumpAndSettle();
      expect(model.remindersOn, isFalse);

      // 5. Ready: the medicine as it will be saved.
      expect(find.text('Insulin'), findsOneWidget);
      expect(find.text('2 units · 8:00 AM'), findsOneWidget);
      await tester.tap(find.text('Go to Today'));
      await tester.pumpAndSettle();
      expect(find.byType(PaywallScreen), findsOneWidget);
      expect(tester.takeException(), isNull);

      // Continuing free saves the pet, then the medicine.
      await tester.tap(find.byTooltip('Continue free'));
      await tester.pumpAndSettle();
      expect(care.pets.single.name, 'Miso');
      expect(care.medications.single.name, 'Insulin');
      expect(care.medications.single.amount, '2 units');
      expect(model.isComplete, isTrue);
      // Free: inviting is Pro, so the address is named, not lost.
      expect(find.textContaining('sara@example.com'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      router.dispose();
      model.dispose();
      care.dispose();
    },
  );

  const screens = <Widget>[
    WelcomeScreen(),
    PetBasicsScreen(),
    FirstMedicineScreen(),
    CaregiversScreen(),
    NotificationsScreen(),
    ReadyScreen(),
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
      final model = OnboardingViewModel()..setName('Miso');
      addTearDown(model.dispose);
      final care = CareRepository();
      addTearDown(care.dispose);

      for (final screen in screens) {
        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider.value(value: model),
              ChangeNotifierProvider.value(value: care),
            ],
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
        // Footer uses the page's 24 px gutters, so the button lines up
        // with the fields above it.
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
