import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pawsitive_sync/app.dart';
import 'package:pawsitive_sync/core/routing/app_router.dart';
import 'package:pawsitive_sync/core/routing/routes.dart';
import 'package:pawsitive_sync/core/theme/app_theme.dart';
import 'package:pawsitive_sync/data/care_repository.dart';
import 'package:pawsitive_sync/domain/models.dart';
import 'package:pawsitive_sync/ui/onboarding/onboarding_view_model.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'support/sample_household.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});
  testWidgets('welcome leads into pet basics', (tester) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => CareRepository()),
          ChangeNotifierProvider(create: (_) => OnboardingViewModel()),
        ],
        child: const PawsitiveApp(),
      ),
    );
    await tester.pump();

    expect(find.text('See who already gave it.'), findsOneWidget);
    expect(find.text('Pawsitive'), findsOneWidget);

    await tester.ensureVisible(find.text('Get started'));
    await tester.tap(find.text('Get started'));
    await tester.pumpAndSettle();

    expect(find.text('Who are we caring for?'), findsOneWidget);
    expect(find.text('Add a name to continue'), findsOneWidget);

    await tester.enterText(find.byType(TextFormField), 'Miso');
    await tester.pump();
    await tester.ensureVisible(find.text('Continue'));
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(find.text('A little about Miso'), findsOneWidget);
  });

  testWidgets('skipped onboarding routes resume at the earliest missing step', (
    tester,
  ) async {
    final onboarding = OnboardingViewModel();
    final router = createRouter(onboarding);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => CareRepository()),
          ChangeNotifierProvider.value(value: onboarding),
        ],
        child: MaterialApp.router(
          theme: AppTheme.light(),
          routerConfig: router,
        ),
      ),
    );

    router.go(AppRoutes.notifications);
    await tester.pumpAndSettle();

    expect(find.text('Who are we caring for?'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    router.dispose();
  });

  testWidgets('welcome fits on a short phone without overflow', (tester) async {
    final errors = <String>[];
    final previous = FlutterError.onError;
    FlutterError.onError = (details) {
      errors.add(details.exceptionAsString());
      previous?.call(details);
    };
    addTearDown(() => FlutterError.onError = previous);

    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => CareRepository()),
          ChangeNotifierProvider(create: (_) => OnboardingViewModel()),
        ],
        child: const PawsitiveApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('See who already gave it.'), findsOneWidget);
    final overflows = errors.where((error) => error.contains('overflowed'));
    expect(overflows, isEmpty, reason: overflows.join('\n'));
  });

  testWidgets('phone width keeps the bottom bar', (tester) async {
    await _pumpHome(tester, const Size(390, 844));
    expect(find.byType(NavigationRail), findsNothing);
    expect(find.text('Today'), findsWidgets);
    expect(find.text('Household'), findsWidgets);
  });

  testWidgets('iPad width uses a navigation rail', (tester) async {
    await _pumpHome(tester, const Size(1024, 1366));
    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.text('Today'), findsWidgets);
  });

  testWidgets('unknown routes offer a way back to today', (tester) async {
    final onboarding = OnboardingViewModel()..finish(reminders: false);
    final router = createRouter(onboarding);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => sampleCare()),
          ChangeNotifierProvider.value(value: onboarding),
        ],
        child: MaterialApp.router(
          theme: AppTheme.light(),
          routerConfig: router,
        ),
      ),
    );
    router.go('/missing-page');
    await tester.pumpAndSettle();

    expect(find.text('That page is not in the app.'), findsOneWidget);
    expect(find.text('Go to today'), findsOneWidget);

    await tester.tap(find.text('Go to today'));
    await tester.pumpAndSettle();
    expect(find.text('Today'), findsWidgets);

    await tester.pumpWidget(const SizedBox.shrink());
    router.dispose();
  });

  testWidgets('fresh home shows quick actions that open without crashing', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final onboarding = OnboardingViewModel()
      ..setName('Biscuit')
      ..toggleCondition('Diabetes')
      ..toggleCaregiver('Just me');
    final care = CareRepository()..applyOnboarding(onboarding);
    await onboarding.finish(reminders: false);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: care),
          ChangeNotifierProvider.value(value: onboarding),
        ],
        child: const PawsitiveApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Add first medicine'), findsOneWidget);

    for (final label in ['My pet', 'Family & helpers', 'Vet report']) {
      final router = GoRouter.of(tester.element(find.byType(Scaffold).first));
      router.go(AppRoutes.today);
      await tester.pumpAndSettle();
      final scrollable = find
          .descendant(
            of: find.byType(ListView).first,
            matching: find.byType(Scrollable),
          )
          .first;
      tester.state<ScrollableState>(scrollable).position.jumpTo(0);
      await tester.scrollUntilVisible(
        find.bySemanticsLabel(label),
        150,
        scrollable: scrollable,
      );
      await tester.tap(find.bySemanticsLabel(label));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: label);
    }
  });

  test('logging a due dose marks it given', () async {
    final care = sampleCare();
    expect(care.givenCount, 3);
    final doseId = CareRepository.doseIdFor('fluids', DayPart.afternoon);
    expect(care.doseById(doseId)?.status, DoseStatus.due);

    final saved = await care.logDose(
      doseId: doseId,
      memberId: 'you',
      amount: '100 ml',
      timeLabel: '1:06 PM',
    );

    expect(saved, isTrue);
    expect(care.doseById(doseId)?.status, DoseStatus.given);
    expect(care.givenCount, 4);
    expect(care.activity.first.actor, 'You');
  });

  test('the same dose cannot be logged twice', () async {
    final care = sampleCare();
    final doseId = CareRepository.doseIdFor('fluids', DayPart.afternoon);
    await care.logDose(
      doseId: doseId,
      memberId: 'you',
      amount: '100 ml',
      timeLabel: '1:06 PM',
    );
    final again = await care.logDose(
      doseId: doseId,
      memberId: 'you',
      amount: '100 ml',
      timeLabel: '1:07 PM',
    );
    expect(again, isFalse);
    expect(care.givenCount, 4);
  });

  test('a new medicine shows on Today and in the vet report', () async {
    // Pro: the sample's Miso already has Free's medicine count.
    final care = sampleCare()..debugStorePro = true;
    final before = care.doses.length;
    final saved = await care.addMedication(
      petId: 'miso',
      name: 'Gabapentin',
      amount: '50 mg',
      parts: const [DayPart.evening],
      supplyTotal: 20,
    );
    expect(saved, isTrue);
    expect(care.doses.length, before + 1);
    expect(care.doses.map((d) => d.name), contains('Gabapentin'));
    expect(
      care.reportFor('miso', 7).lines.map((l) => l.medication.name),
      contains('Gabapentin'),
    );
  });

  test('free tier blocks a second pet', () async {
    final care = sampleCare();
    final blocked = await care.addPet(
      name: 'Pepper',
      species: Species.dog,
      ageYears: 3,
      weightKg: 12,
    );
    expect(blocked, isNull);
    expect(care.canAddPet, isFalse);
  });

  test('a new pet can be added after setup with Pro', () async {
    final care = sampleCare();
    care.applyStoreEntitlement(true, BillingPlan.yearly);
    final id = await care.addPet(
      name: 'Pepper',
      species: Species.dog,
      ageYears: 3,
      weightKg: 12,
    );
    expect(id, isNotNull);
    expect(care.tryPetById(id!)?.name, 'Pepper');
  });

  testWidgets('every screen lays out on a phone and a wide window', (
    tester,
  ) async {
    final errors = <String>[];
    final previous = FlutterError.onError;
    FlutterError.onError = (details) {
      errors.add(details.exceptionAsString());
      previous?.call(details);
    };
    addTearDown(() => FlutterError.onError = previous);

    const paths = [
      AppRoutes.today,
      AppRoutes.pets,
      AppRoutes.household,
      AppRoutes.reports,
      AppRoutes.schedule,
      AppRoutes.invite,
      AppRoutes.join,
      AppRoutes.addPet,
      '/edit-pet/miso',
      AppRoutes.settings,
      AppRoutes.lock,
      '/medication/insulin',
      AppRoutes.paywall,
    ];

    for (final size in const [Size(360, 780), Size(1024, 1366)]) {
      await _pumpHome(tester, size);
      final router = GoRouter.of(tester.element(find.byType(Scaffold).first));
      for (final path in paths) {
        router.go(path);
        await tester.pumpAndSettle();
        expect(find.byType(Scaffold), findsWidgets, reason: '$path at $size');
      }
    }

    final overflows = errors.where((error) => error.contains('overflowed'));
    expect(overflows, isEmpty, reason: overflows.join('\n'));
  });
}

Future<void> _pumpHome(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final onboarding = OnboardingViewModel()..finish(reminders: false);
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => sampleCare()),
        ChangeNotifierProvider.value(value: onboarding),
      ],
      child: const PawsitiveApp(),
    ),
  );
  await tester.pumpAndSettle();
}
