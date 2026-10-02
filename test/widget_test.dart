import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pawsitive_sync/app.dart';
import 'package:pawsitive_sync/core/routing/app_router.dart';
import 'package:pawsitive_sync/core/routing/routes.dart';
import 'package:pawsitive_sync/core/theme/app_theme.dart';
import 'package:pawsitive_sync/data/care_repository.dart';
import 'package:pawsitive_sync/ui/onboarding/onboarding_view_model.dart';
import 'package:provider/provider.dart';

void main() {
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
    expect(find.text('Morning insulin'), findsOneWidget);

    await tester.ensureVisible(find.text('Get started'));
    await tester.tap(find.text('Get started'));
    await tester.pumpAndSettle();

    expect(find.text('Who are we caring for?'), findsOneWidget);
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
          ChangeNotifierProvider(create: (_) => CareRepository()),
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

  test('logging a due dose marks it given', () {
    final care = CareRepository();
    expect(care.givenCount, 3);

    care.logDose(
      doseId: 'fluids-pm',
      memberId: 'you',
      amount: '100 ml',
      timeLabel: '1:06 PM',
    );

    final dose = care.doseById('fluids-pm');
    expect(dose?.status.name, 'given');
    expect(care.givenCount, 4);
    expect(care.activity.first.actor, 'You');
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
        ChangeNotifierProvider(create: (_) => CareRepository()),
        ChangeNotifierProvider.value(value: onboarding),
      ],
      child: const PawsitiveApp(),
    ),
  );
  await tester.pumpAndSettle();
}
