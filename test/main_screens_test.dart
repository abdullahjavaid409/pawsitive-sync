import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pawsitive_sync/core/format/clock_format.dart';
import 'package:pawsitive_sync/core/logging/app_log.dart';
import 'package:pawsitive_sync/core/routing/app_router.dart';
import 'package:pawsitive_sync/core/routing/routes.dart';
import 'package:pawsitive_sync/core/theme/app_theme.dart';
import 'package:pawsitive_sync/core/widgets/care_widgets.dart';
import 'package:pawsitive_sync/data/care_repository.dart';
import 'package:pawsitive_sync/domain/models.dart';
import 'package:pawsitive_sync/ui/onboarding/onboarding_view_model.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/sample_household.dart';

import 'support/app_fonts.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppLog.enableTestCapture();
  });
  tearDown(AppLog.disableTestCapture);

  testWidgets('pet filter updates daily progress and next dose together', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final care = sampleCare(clock: () => DateTime(2026, 10, 3, 14));
    await _pump(tester, care);
    String progress([String? petId]) {
      final doses = care.doses.where((d) => petId == null || d.petId == petId);
      final given = doses.where((d) => d.status == DoseStatus.given).length;
      return '$given of ${doses.length} doses given today';
    }

    // v14 progress card: "X of Y doses given today" and one next action.
    expect(find.bySemanticsLabel(progress()), findsOneWidget);
    expect(find.text('Mark given'), findsOneWidget);
    await tester.tap(find.text('Juniper'));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel(progress('juniper')), findsOneWidget);
    expect(find.text('Everyone is covered for today'), findsOneWidget);
    expect(find.text('Mark given'), findsNothing);
    await tester.tap(find.text('All pets'));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel(progress()), findsOneWidget);
    handle.dispose();
  });

  testWidgets('a due dose inside a group opens confirmation without logging', (
    tester,
  ) async {
    // Pro: the sample’s Miso already has Free’s medicine count.
    final care = sampleCare(clock: () => DateTime(2026, 10, 3, 14))
      ..debugStorePro = true;
    await care.addMedication(
      petId: 'miso',
      name: 'Gabapentin',
      amount: '50 mg',
      parts: [DayPart.afternoon],
      supplyTotal: 20,
    );
    await _pump(tester, care);
    final dose = care.doses.firstWhere((d) => d.name == 'Gabapentin');
    // v14 rows show the medicine name; pet, amount and time sit below it.
    await tester.scrollUntilVisible(
      find.text(dose.name),
      200,
      scrollable: _verticalScroll(),
    );
    await Scrollable.ensureVisible(
      tester.element(find.text(dose.name)),
      alignment: 0.5,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text(dose.name));
    await tester.pumpAndSettle();
    expect(find.text('Log Miso’s Gabapentin?'), findsOneWidget);
    expect(care.doseById(dose.id)!.status, DoseStatus.due);
    expect(tester.takeException(), isNull);
  });

  testWidgets('upcoming doses offer details without a give-now action', (
    tester,
  ) async {
    final care = sampleCare(clock: () => DateTime(2026, 10, 3, 7));
    await _pump(tester, care);
    expect(find.textContaining('Later today'), findsOneWidget);
    expect(find.text('View medicine'), findsOneWidget);
    expect(find.text('Mark given'), findsNothing);
    // Rows for later doses say so instead of offering "Give".
    expect(find.text('Give'), findsNothing);
  });

  testWidgets('a pet with no report can switch back to a pet with records', (
    tester,
  ) async {
    final care = sampleCare(clock: () => DateTime(2026, 10, 3, 14));
    care.applyStoreEntitlement(true, BillingPlan.yearly);
    // A removed medicine keeps its in-range history in the report, so the
    // empty state needs a pet that never had a medicine.
    await care.addPet(name: 'Pip', species: Species.rabbit);
    final router = await _pump(tester, care);
    router.go(AppRoutes.reports);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Pip'));
    await tester.tap(find.text('Pip'));
    await tester.pumpAndSettle();
    expect(find.byType(CareEmptyState), findsOneWidget);
    // The pet switch stays in the header so the way back is never lost.
    await tester.ensureVisible(find.text('Miso'));
    await tester.tap(find.text('Miso'));
    await tester.pumpAndSettle();
    expect(find.text('By medicine'), findsOneWidget);
    expect(find.byType(CareEmptyState), findsNothing);
  });

  testWidgets('medicine flow saves the selected pet, daily times and supply', (
    tester,
  ) async {
    // Pro: Juniper already has Free’s one medicine.
    final care = sampleCare(clock: () => DateTime(2026, 10, 3, 14))
      ..debugStorePro = true;
    final router = await _pump(tester, care);
    router.go('${AppRoutes.schedule}?pet=juniper');
    await tester.pumpAndSettle();
    expect(find.text('For Juniper'), findsOneWidget);
    // 1. Name
    await tester.enterText(find.byType(TextField), 'Eye drops');
    await _continue(tester);
    // 2. Form sets the unit
    await tester.tap(find.text('Drops'));
    await _continue(tester);
    // 3. Amount, and where drops go (required for drops)
    await tester.enterText(find.byType(TextField).first, '1');
    await tester.pumpAndSettle();
    expect(find.text('Choose where it’s given.'), findsOneWidget);
    await tester.tap(find.text('Left eye'));
    await _continue(tester);
    // 4. When
    await _reveal(tester, find.text('Evening'));
    await tester.tap(find.text('Evening'));
    await _reveal(tester, find.text('7 days'));
    await tester.tap(find.text('7 days'));
    await _reveal(tester, find.text('Track remaining doses'));
    await tester.tap(find.text('Track remaining doses'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '30');
    await _continue(tester);
    // 5. Review, then save
    expect(find.text('Look right?'), findsOneWidget);
    expect(find.text('1 drop'), findsOneWidget);
    await tester.tap(find.text('Save medicine'));
    await tester.pumpAndSettle();
    final medicine = care.medications.singleWhere((m) => m.name == 'Eye drops');
    expect(medicine.petId, 'juniper');
    expect(medicine.amount, '1 drop');
    expect(medicine.site, 'Left eye');
    expect(medicine.everyDays, 1);
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

  testWidgets('review edits jump back and return to the review', (
    tester,
  ) async {
    final care = sampleCare(clock: () => DateTime(2026, 10, 3, 14))
      ..debugStorePro = true;
    final router = await _pump(tester, care);
    router.go('${AppRoutes.schedule}?pet=juniper');
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Gabapentin');
    for (var i = 0; i < 4; i++) {
      await _continue(tester);
    }
    expect(find.text('As prescribed'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Edit each dose'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '0.5');
    await tester.tap(find.text('Back to review'));
    await tester.pumpAndSettle();
    expect(find.text('½ tablet'), findsOneWidget);
  });

  testWidgets('Free: evening dose time opens the paywall, not the schedule', (
    tester,
  ) async {
    final care = CareRepository(clock: () => DateTime(2026, 10, 3, 14));
    final petId = (await care.addPet(name: 'Pip', species: Species.cat))!;
    final router = await _pump(tester, care);
    router.go('${AppRoutes.schedule}?pet=$petId');
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Methimazole');
    for (var i = 0; i < 3; i++) {
      await _continue(tester);
    }
    expect(
      find.text(
        'Free includes one morning dose (4 AM to noon) and its reminder. Pro adds afternoon, evening and any time.',
      ),
      findsOneWidget,
    );
    // Afternoon and evening say "Pro" before anyone taps them.
    expect(
      find.bySemanticsLabel(RegExp(r'^Evening, .*, Pro$')),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel(RegExp(r'^Afternoon, .*, Pro$')),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel(RegExp(r'^Morning, .*, Pro$')), findsNothing);
    await _reveal(tester, find.text('Evening'));
    await tester.tap(find.text('Evening'));
    await tester.pumpAndSettle();
    expect(find.text('Morning and evening, both covered'), findsOneWidget);
    expect(AppLog.logged('medication.add.blocked'), isTrue);
    expect(care.medications, isEmpty);
  });

  testWidgets(
    'medicine flow explains missing details and optional supply can be removed',
    (tester) async {
      // Pro: Free at its medicine cap opens the paywall instead (own test).
      final care = sampleCare()..debugStorePro = true;
      final initialCount = care.medications.length;
      final router = await _pump(tester, care);
      router.go(AppRoutes.schedule);
      await tester.pumpAndSettle();
      // No name: Continue is off and says why.
      expect(
        find.text('Type a name or pick one from the list'),
        findsOneWidget,
      );
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(find.text('What’s the medicine called?'), findsOneWidget);
      expect(care.medications.length, initialCount);
      await tester.enterText(find.byType(TextField).first, 'New medicine');
      await _continue(tester);
      await _continue(tester);
      // A split capsule is refused with a reason.
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Capsule'));
      await _continue(tester);
      await tester.enterText(find.byType(TextField).first, '1.5');
      await tester.pumpAndSettle();
      expect(
        find.text('A capsule can’t be split. Use a whole number.'),
        findsWidgets,
      );
      await tester.enterText(find.byType(TextField).first, '');
      await _continue(tester);
      await _reveal(tester, find.text('Morning'));
      await tester.tap(find.text('Morning'));
      await tester.pumpAndSettle();
      expect(find.text('Select at least one time of day.'), findsOneWidget);
      await tester.tap(find.text('Afternoon'));
      await _reveal(tester, find.text('Track remaining doses'));
      await tester.tap(find.text('Track remaining doses'));
      await tester.pumpAndSettle();
      expect(find.text('Enter the number of doses left.'), findsOneWidget);
      await tester.enterText(find.byType(TextField).last, '12');
      tester.testTextInput.hide();
      await _reveal(tester, find.text('Track remaining doses'));
      await tester.tap(find.text('Track remaining doses'));
      await _continue(tester);
      await tester.tap(find.text('Save medicine'));
      await tester.pumpAndSettle();
      final medicine = care.medications.singleWhere(
        (m) => m.name == 'New medicine',
      );
      expect(medicine.supplyTotal, 0);
      expect(medicine.amount, '');
      expect(medicine.parts, [DayPart.afternoon]);
    },
  );

  testWidgets(
    'first care event is discoverable, saves notes and confirms removal',
    (tester) async {
      final care = sampleCare(clock: () => DateTime(2026, 10, 3, 14));
      await _pump(tester, care);
      // v14: "Coming up" lives on the pet's page, not Today.
      await tester.tap(find.text('Pets').last);
      await tester.pumpAndSettle();
      await _reveal(tester, find.text('Add event'));
      await tester.tap(find.text('Add event'));
      await tester.pumpAndSettle();
      expect(find.text('Add care event'), findsOneWidget);
      await tester.tap(find.text('Vet visit'));
      await tester.pump();
      await tester.enterText(find.byType(TextField).first, 'Annual checkup');
      await tester.enterText(
        find.byType(TextField).last,
        'Bring the care report',
      );
      tester.testTextInput.hide();
      await tester.tap(find.text('Save event'));
      await tester.pumpAndSettle();
      expect(care.careEvents, hasLength(1));
      expect(care.careEvents.single.dueDay, '2026-10-10');
      expect(care.careEvents.single.note, 'Bring the care report');
      await _reveal(tester, find.text('Annual checkup'));
      await tester.tap(find.byTooltip('Remove Annual checkup'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(care.careEvents, hasLength(1));
      await tester.tap(find.byTooltip('Remove Annual checkup'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove'));
      await tester.pumpAndSettle();
      expect(care.careEvents, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('today shows every dose state: hero, rounds and the log', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    // 14:00: morning given (Sara, Dan), afternoon fluids due, evening
    // insulin later. Fluids is then marked "not sure".
    final care = sampleCare(clock: () => DateTime(2026, 10, 3, 14));
    await care.markDoseUncertain('fluids.afternoon');
    await _pump(tester, care);

    // The progress card answers first: the "not sure" dose needs a check.
    expect(find.textContaining('Needs a check'), findsOneWidget);
    expect(find.text('Review dose'), findsOneWidget);
    // Morning / Afternoon / Evening groups, as in v14.
    expect(find.text('Morning'), findsOneWidget);
    // Who gave each dose sits on its line, in plain words.
    expect(find.textContaining('Sara · 8:02 AM'), findsOneWidget);
    expect(find.textContaining('Dan · 8:30 AM'), findsOneWidget);
    // Every state reads out for VoiceOver, ending with its state.
    for (final state in [
      RegExp('given by Sara at 8:02 AM\$'),
      RegExp('needs a check\$'),
      RegExp('later\$'),
    ]) {
      expect(find.bySemanticsLabel(state), findsWidgets, reason: '$state');
    }
    // "Not sure" keeps its full warning on the line.
    expect(find.textContaining('not sure — check first'), findsWidgets);
    // v14 keeps Today to doses: adding a medicine lives on Pets.
    expect(find.text('Add medicine'), findsNothing);

    // One pet: only its lines remain.
    await tester.drag(_verticalScroll(), const Offset(0, 2000));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Juniper'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Dan · 8:30 AM'), findsOneWidget);
    expect(find.textContaining('Sara · 8:02 AM'), findsNothing);
    expect(tester.takeException(), isNull);
    handle.dispose();
  });

  testWidgets('today ledger follows a 24-hour clock', (tester) async {
    ClockFormat.use24h.value = true;
    addTearDown(() => ClockFormat.use24h.value = false);
    final care = sampleCare(clock: () => DateTime(2026, 10, 3, 14));
    await _pump(tester, care);
    expect(find.textContaining('08:00'), findsWidgets);
    expect(find.textContaining('8:00 AM'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('today ledger fits a small phone at large text', (tester) async {
    final care = sampleCare(clock: () => DateTime(2026, 10, 3, 14));
    await _pump(tester, care, size: const Size(320, 640), scale: 2);
    for (var page = 0; page < 6; page++) {
      await tester.drag(_verticalScroll(), const Offset(0, -300));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'page $page');
    }
  });

  testWidgets('uncertain doses are clearly marked for review', (tester) async {
    final care = sampleCare(clock: () => DateTime(2026, 10, 3, 14));
    final dose = care.nextDue!;
    await care.markDoseUncertain(dose.id);
    await _pump(tester, care);
    expect(find.textContaining('Needs a check'), findsOneWidget);
    expect(find.text('Review dose'), findsOneWidget);
    await tester.tap(find.text('Review dose'));
    await tester.pumpAndSettle();
    final pet = care.tryPetById(dose.petId)!.name;
    expect(find.text('Log $pet’s ${dose.name}?'), findsOneWidget);
    expect(care.doseById(dose.id)!.status, DoseStatus.due);
  });

  testWidgets('care event sheet supports large text with the keyboard open', (
    tester,
  ) async {
    final care = sampleCare();
    await _pump(tester, care, size: const Size(320, 640), scale: 1.6);
    await tester.tap(find.text('Pets').last);
    await tester.pumpAndSettle();
    await _reveal(tester, find.text('Add event'));
    await tester.tap(find.text('Add event'));
    await tester.pumpAndSettle();
    tester.view.viewInsets = const FakeViewPadding(bottom: 280);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();
    expect(find.text('Save event').hitTestable(), findsOneWidget);
    final scroll = find
        .descendant(
          of: find
              .byWidgetPredicate(
                (widget) =>
                    widget is SingleChildScrollView &&
                    widget.scrollDirection == Axis.vertical,
              )
              .last,
          matching: find.byType(Scrollable),
        )
        .first;
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
      final care = sampleCare(clock: () => DateTime(2026, 10, 3, 14));
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

  testWidgets('settings has no demo-data or debug controls', (tester) async {
    final care = CareRepository(clock: () => DateTime(2026, 10, 3, 14));
    final router = await _pump(tester, care);
    router.go(AppRoutes.settings);
    await tester.pumpAndSettle();
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -2000));
    await tester.pumpAndSettle();
    expect(find.textContaining('demo', findRichText: true), findsNothing);
    expect(find.textContaining('DEBUG'), findsNothing);
    expect(care.pets, isEmpty);
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

Future<GoRouter> _pump(
  WidgetTester tester,
  CareRepository care, {
  Size size = const Size(390, 844),
  double scale = 1,
  bool dark = false,
}) async {
  await loadAppFonts();
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

/// Taps the flow's Continue (or Back to review) and lets the step settle.
Future<void> _continue(WidgetTester tester) async {
  await tester.pumpAndSettle();
  final next = find.text('Continue').evaluate().isNotEmpty
      ? find.text('Continue')
      : find.text('Back to review');
  await tester.tap(next);
  await tester.pumpAndSettle();
}
