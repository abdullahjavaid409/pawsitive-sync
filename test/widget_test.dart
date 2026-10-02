import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pawsitive_sync/app.dart';
import 'package:pawsitive_sync/core/routing/app_router.dart';
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

    expect(
      find.text('Every dose, seen by everyone who cares for them.'),
      findsOneWidget,
    );

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
