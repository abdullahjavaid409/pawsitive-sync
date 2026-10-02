import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pawsitive_sync/core/routing/app_router.dart';
import 'package:pawsitive_sync/core/routing/routes.dart';
import 'package:pawsitive_sync/core/theme/app_theme.dart';
import 'package:pawsitive_sync/core/widgets/care_widgets.dart';
import 'package:pawsitive_sync/data/care_repository.dart';
import 'package:pawsitive_sync/domain/models.dart';
import 'package:pawsitive_sync/ui/onboarding/onboarding_view_model.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('pet filter updates daily progress and next dose together', (
    tester,
  ) async {
    final care = CareRepository.sample(clock: () => DateTime(2026, 10, 3, 14));
    await _pump(tester, care);
    expect(find.text('2 doses left today'), findsOneWidget);
    expect(find.text('Log dose'), findsOneWidget);
    await tester.tap(find.text('Juniper'));
    await tester.pumpAndSettle();
    expect(find.text('All cared for.'), findsOneWidget);
    expect(find.text('Log dose'), findsNothing);
    await tester.tap(find.text('All pets'));
    await tester.pumpAndSettle();
    expect(find.text('2 doses left today'), findsOneWidget);
  });

  testWidgets('a due dose inside a group opens confirmation without logging', (
    tester,
  ) async {
    final care = CareRepository.sample(clock: () => DateTime(2026, 10, 3, 14));
    await care.addMedication(
      petId: 'miso',
      name: 'Gabapentin',
      amount: '50 mg',
      parts: [DayPart.afternoon],
      supplyTotal: 20,
    );
    await _pump(tester, care);
    final dose = care.doses.firstWhere((d) => d.name == 'Gabapentin');
    await tester.scrollUntilVisible(
      find.text(dose.title),
      200,
      scrollable: _verticalScroll(),
    );
    await Scrollable.ensureVisible(
      tester.element(find.text(dose.title)),
      alignment: 0.5,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text(dose.title));
    await tester.pumpAndSettle();
    expect(find.text('Log gabapentin'), findsOneWidget);
    expect(care.doseById(dose.id)!.status, DoseStatus.due);
    expect(tester.takeException(), isNull);
  });

  testWidgets('upcoming doses offer details without a give-now action', (
    tester,
  ) async {
    final care = CareRepository.sample(clock: () => DateTime(2026, 10, 3, 7));
    await _pump(tester, care);
    expect(find.text('Later today'), findsOneWidget);
    expect(find.text('View medicine'), findsOneWidget);
    expect(find.text('Log dose'), findsNothing);
  });

  testWidgets('a pet with no report can switch back to a pet with records', (
    tester,
  ) async {
    final care = CareRepository.sample(clock: () => DateTime(2026, 10, 3, 14));
    await care.startTrial();
    for (final medicine in care.medicationsFor('juniper')) {
      await care.removeMedication(medicine.id);
    }
    final router = await _pump(tester, care);
    router.go(AppRoutes.reports);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Juniper'));
    await tester.tap(find.text('Juniper'));
    await tester.pumpAndSettle();
    expect(find.byType(CareEmptyState), findsOneWidget);
    expect(find.byType(CarePetPicker), findsOneWidget);
    await tester.ensureVisible(find.text('Miso'));
    await tester.tap(find.text('Miso'));
    await tester.pumpAndSettle();
    expect(find.text('Medication record'), findsOneWidget);
    expect(find.byType(CareEmptyState), findsNothing);
  });

  testWidgets('medicine form saves the selected pet, daily times and supply', (
    tester,
  ) async {
    final care = CareRepository.sample(clock: () => DateTime(2026, 10, 3, 14));
    final router = await _pump(tester, care);
    router.go('${AppRoutes.schedule}?pet=juniper');
    await tester.pumpAndSettle();
    expect(find.text('A simple routine for Juniper.'), findsOneWidget);
    expect(tester.testTextInput.isVisible, isFalse);
    await tester.enterText(find.byType(TextFormField).at(0), 'Eye drops');
    await tester.enterText(find.byType(TextFormField).at(1), '1 drop');
    tester.testTextInput.hide();
    await _reveal(tester, find.text('Evening'));
    await tester.tap(find.text('Evening'));
    await _reveal(tester, find.text('7 days'));
    await tester.tap(find.text('7 days'));
    await _reveal(tester, find.text('Track remaining doses'));
    await tester.tap(find.text('Track remaining doses'));
    await tester.pumpAndSettle();
    await _reveal(tester, find.text('Doses remaining'));
    await tester.enterText(find.byType(TextFormField).last, '30');
    await tester.tap(find.text('Save medicine'));
    await tester.pumpAndSettle();
    final medicine = care.medications.singleWhere((m) => m.name == 'Eye drops');
    expect(medicine.petId, 'juniper');
    expect(medicine.amount, '1 drop');
    expect(medicine.parts, [DayPart.morning, DayPart.evening]);
    expect(medicine.supplyTotal, 30);
    expect(medicine.endDay, '2026-10-09');
    expect(medicine.isActiveOn('2026-10-09'), isTrue);
    expect(medicine.isActiveOn('2026-10-10'), isFalse);
    expect(
      care.doses.where((d) => d.medicationId == medicine.id),
      hasLength(2),
    );
  });

  testWidgets(
    'medicine validation explains missing details and optional supply can be removed',
    (tester) async {
      final care = CareRepository.sample();
      final initialCount = care.medications.length;
      final router = await _pump(tester, care);
      router.go(AppRoutes.schedule);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save medicine'));
      await tester.pumpAndSettle();
      expect(find.text('Enter the medicine name.'), findsOneWidget);
      expect(care.medications.length, initialCount);
      await tester.enterText(find.byType(TextFormField).first, 'New medicine');
      tester.testTextInput.hide();
      await _reveal(tester, find.text('Morning'));
      await tester.tap(find.text('Morning'));
      await tester.tap(find.text('Save medicine'));
      await tester.pumpAndSettle();
      expect(find.text('Select at least one time of day.'), findsOneWidget);
      await _reveal(tester, find.text('Afternoon'));
      await tester.tap(find.text('Afternoon'));
      await _reveal(tester, find.text('Track remaining doses'));
      await tester.tap(find.text('Track remaining doses'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save medicine'));
      await tester.pumpAndSettle();
      expect(find.text('Enter the number of doses left.'), findsOneWidget);
      await tester.enterText(find.byType(TextFormField).last, '12');
      tester.testTextInput.hide();
      await _reveal(tester, find.text('Track remaining doses'));
      await tester.tap(find.text('Track remaining doses'));
      await tester.tap(find.text('Save medicine'));
      await tester.pumpAndSettle();
      final medicine = care.medications.singleWhere(
        (m) => m.name == 'New medicine',
      );
      expect(medicine.supplyTotal, 0);
      expect(medicine.parts, [DayPart.afternoon]);
    },
  );

  testWidgets('first care event is discoverable, saves notes and confirms removal', (tester) async {
    final care = CareRepository.sample(clock: () => DateTime(2026, 10, 3, 14));
    await _pump(tester, care);
    await _reveal(tester, find.text('Add event'));
    await tester.tap(find.text('Add event'));
    await tester.pumpAndSettle();
    expect(find.text('Add care event'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, 'Annual checkup');
    await tester.enterText(find.byType(TextField).last, 'Bring the care report');
    tester.testTextInput.hide();
    await tester.tap(find.text('Save event'));
    await tester.pumpAndSettle();
    expect(care.careEvents, hasLength(1));
    expect(care.careEvents.single.dueDay, '2026-10-10');
    expect(care.careEvents.single.note, 'Bring the care report');
    await _reveal(tester, find.text('Annual checkup'));
    await tester.tap(find.byTooltip('Remove Annual checkup'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Keep event'));
    await tester.pumpAndSettle();
    expect(care.careEvents, hasLength(1));
    await tester.tap(find.byTooltip('Remove Annual checkup'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();
    expect(care.careEvents, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('uncertain doses are clearly marked for review', (tester) async {
    final care = CareRepository.sample(clock: () => DateTime(2026, 10, 3, 14));
    final dose = care.nextDue!;
    await care.markDoseUncertain(dose.id);
    await _pump(tester, care);
    expect(find.text('Needs a check'), findsOneWidget);
    expect(find.text('Review dose'), findsOneWidget);
    await tester.tap(find.text('Review dose'));
    await tester.pumpAndSettle();
    expect(find.text('Log ${dose.name.toLowerCase()}'), findsOneWidget);
    expect(care.doseById(dose.id)!.status, DoseStatus.due);
  });

  testWidgets('care event sheet supports large text with the keyboard open', (tester) async {
    final care = CareRepository.sample();
    await _pump(tester, care, size: const Size(320, 640), scale: 1.6);
    await _reveal(tester, find.text('Add event'));
    await tester.tap(find.text('Add event'));
    await tester.pumpAndSettle();
    tester.view.viewInsets = const FakeViewPadding(bottom: 280);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();
    expect(find.text('Save event').hitTestable(), findsOneWidget);
    final scroll = find.descendant(of: find.byWidgetPredicate((widget) => widget is SingleChildScrollView && widget.scrollDirection == Axis.vertical).last, matching: find.byType(Scrollable)).first;
    for (var page = 0; page < 5; page++) {
      await tester.drag(scroll, const Offset(0, -180));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
  });

  for (final scenario in [
    (size: const Size(320, 640), scale: 1.6, dark: false),
    (size: const Size(390, 844), scale: 1.0, dark: true),
  ]) {
    testWidgets('main tabs scroll without overflow at $scenario', (
      tester,
    ) async {
      final care = CareRepository.sample(
        clock: () => DateTime(2026, 10, 3, 14),
      );
      final router = await _pump(
        tester,
        care,
        size: scenario.size,
        scale: scenario.scale,
        dark: scenario.dark,
      );
      for (final route in [
        AppRoutes.today,
        AppRoutes.pets,
        AppRoutes.household,
        AppRoutes.reports,
        AppRoutes.schedule,
        AppRoutes.medication('insulin'),
      ]) {
        router.go(route);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: route);
        final scrollable = _verticalScroll();
        for (var page = 0; page < 8; page++) {
          await tester.drag(scrollable, const Offset(0, -350));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: '$route page $page');
        }
      }
    });
  }
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

Future<GoRouter> _pump(
  WidgetTester tester,
  CareRepository care, {
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
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    router.dispose();
    model.dispose();
    care.dispose();
  });
  return router;
}
