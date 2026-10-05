import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pawsitive_sync/core/format/clock_format.dart';
import 'package:pawsitive_sync/core/logging/app_log.dart';
import 'package:pawsitive_sync/core/routing/app_router.dart';
import 'package:pawsitive_sync/core/routing/routes.dart';
import 'package:pawsitive_sync/core/theme/app_theme.dart';
import 'package:pawsitive_sync/data/care_repository.dart';
import 'package:pawsitive_sync/domain/models.dart';
import 'package:pawsitive_sync/ui/onboarding/onboarding_view_model.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_log_helpers.dart';
import 'support/sample_household.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppLog.enableTestCapture();
  });
  tearDown(() {
    AppLog.disableTestCapture();
    ClockFormat.resetForTest();
  });

  /// Picks [hour]:[minute] (AM, as the initial times are) in the open
  /// system time picker via its keyboard entry mode.
  Future<void> pickTime(WidgetTester tester, int hour, int minute) async {
    await tester.tap(find.byIcon(Icons.keyboard_outlined));
    await tester.pumpAndSettle();
    final fields = find.descendant(
      of: find.byType(Dialog),
      matching: find.byType(TextField),
    );
    await tester.enterText(fields.at(0), '$hour');
    await tester.enterText(fields.at(1), minute.toString().padLeft(2, '0'));
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'add medicine: pick 7:15 AM for the morning dose, saved and shown',
    (tester) async {
      // Pro: the sample’s Miso already has Free’s medicine count.
      final care = sampleCare(clock: () => DateTime(2026, 10, 3, 6))
        ..debugStorePro = true;
      final router = await _pump(tester, care);
      router.go('${AppRoutes.schedule}?pet=miso');
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).at(0), 'Thyroid');
      tester.testTextInput.hide();
      // Default time shows on the tile and in its own row.
      await _reveal(tester, find.text('Morning reminder'));
      expect(find.text('8:00 AM'), findsWidgets);
      await tester.tap(find.text('Morning reminder'));
      await tester.pumpAndSettle();
      expect(
        find.text('Morning reminder'),
        findsWidgets,
        reason: 'picker title',
      );
      await pickTime(tester, 7, 15);
      expectLogged(
        'medication.time_picked',
        fields: {'part': 'morning', 'custom': true},
      );
      expect(find.text('7:15 AM'), findsWidgets);
      await _reveal(tester, find.text('Save medicine'));
      await tester.tap(find.text('Save medicine'));
      await tester.pumpAndSettle();
      final med = care.medications.singleWhere((m) => m.name == 'Thyroid');
      expect(med.times, {DayPart.morning: 7 * 60 + 15});
      final dose = care.doseById('${med.id}.morning')!;
      expect(dose.timeLabel, '7:15 AM');
      expect(dose.status, DoseStatus.due, reason: 'morning opens at midnight');
    },
  );

  testWidgets('dismissing the picker keeps the default', (tester) async {
    // Pro: the sample’s Miso already has Free’s medicine count.
    final care = sampleCare(clock: () => DateTime(2026, 10, 3, 6))
      ..debugStorePro = true;
    final router = await _pump(tester, care);
    router.go('${AppRoutes.schedule}?pet=miso');
    await tester.pumpAndSettle();
    await _reveal(tester, find.text('Morning reminder'));
    await tester.tap(find.text('Morning reminder'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expectLogged('medication.time_pick_cancelled', fields: {'part': 'morning'});
    expect(find.text('8:00 AM'), findsWidgets);
  });

  testWidgets('medicine screen: change the evening time; Today follows', (
    tester,
  ) async {
    final care = sampleCare(clock: () => DateTime(2026, 10, 3, 6));
    final router = await _pump(tester, care);
    router.go('/medication/insulin');
    await tester.pumpAndSettle();
    await _reveal(tester, find.text('Evening reminder'));
    expect(find.text('8:00 PM'), findsOneWidget);
    await tester.tap(find.text('Evening reminder'));
    await tester.pumpAndSettle();
    // 7:00 PM: PM is kept from the initial 8:00 PM.
    await pickTime(tester, 7, 0);
    expect(find.text('Evening reminder set to 7:00 PM.'), findsOneWidget);
    expect(care.medicationById('insulin')!.times, {DayPart.evening: 19 * 60});
    expectLogged('medication.times.completed', fields: {'customTimes': 1});
    expect(care.doseById('insulin.evening')!.subtitle, 'Miso · 7:00 PM');
  });

  testWidgets('24-hour phones see 19:00, not 7:00 PM', (tester) async {
    final care = sampleCare(clock: () => DateTime(2026, 10, 3, 6));
    await care.setMedicationTimes('insulin', {DayPart.evening: 19 * 60});
    ClockFormat.use24h.value = true;
    final router = await _pump(tester, care);
    router.go('/medication/insulin');
    await tester.pumpAndSettle();
    await _reveal(tester, find.text('Evening reminder'));
    expect(find.text('19:00'), findsOneWidget);
  });
}

Finder _verticalScroll() => find
    .descendant(
      of: find.byType(ListView).first,
      matching: find.byType(Scrollable),
    )
    .first;

Future<void> _reveal(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(finder, 150, scrollable: _verticalScroll());
  await Scrollable.ensureVisible(tester.element(finder), alignment: 0.4);
  await tester.pumpAndSettle();
}

Future<GoRouter> _pump(WidgetTester tester, CareRepository care) async {
  final font = FontLoader('Geist');
  for (final weight in ['Regular', 'Medium', 'SemiBold']) {
    font.addFont(rootBundle.load('assets/fonts/Geist-$weight.ttf'));
  }
  await font.load();
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final model = OnboardingViewModel()..isComplete = true;
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
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    router.dispose();
    model.dispose();
    care.dispose();
  });
  return router;
}
