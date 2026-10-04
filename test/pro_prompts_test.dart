import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pawsitive_sync/core/logging/app_log.dart';
import 'package:pawsitive_sync/core/routing/app_router.dart';
import 'package:pawsitive_sync/core/routing/routes.dart';
import 'package:pawsitive_sync/core/theme/app_theme.dart';
import 'package:pawsitive_sync/core/widgets/pro_lock.dart';
import 'package:pawsitive_sync/data/care_repository.dart';
import 'package:pawsitive_sync/data/pro_prompts.dart';
import 'package:pawsitive_sync/domain/models.dart';
import 'package:pawsitive_sync/domain/paywall_reason.dart';
import 'package:pawsitive_sync/ui/onboarding/onboarding_view_model.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_log_helpers.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppLog.enableTestCapture();
  });
  tearDown(AppLog.disableTestCapture);

  group('auto prompt limits', () {
    test('each trigger once ever; at most one auto prompt per 3 days', () async {
      final t = DateTime(2026, 10, 4, 9);
      expect(await ProPrompts.tryAuto('uncertain', now: t), isTrue);
      expectLogged('billing.prompt.shown', fields: {'trigger': 'uncertain'});
      expect(await ProPrompts.tryAuto('uncertain', now: t.add(const Duration(days: 30))), isFalse);
      expectLogged('billing.prompt.suppressed', fields: {'reason': 'already_shown'});
      expect(await ProPrompts.tryAuto('other', now: t.add(const Duration(days: 2))), isFalse);
      expectLogged('billing.prompt.suppressed', fields: {'reason': 'cooldown'});
      expect(await ProPrompts.tryAuto('other', now: t.add(const Duration(days: 3))), isTrue);
    });

    test('a clock set back is "too soon", never a free pass', () async {
      final t = DateTime(2026, 10, 4, 9);
      expect(await ProPrompts.tryAuto('a', now: t), isTrue);
      expect(await ProPrompts.tryAuto('b', now: DateTime(2026, 1, 1)), isFalse);
    });

    test('first week: once a day (not install day), then once a week', () async {
      final t = DateTime(2026, 10, 4, 9);
      // First idle visit only records the install time.
      expect(await ProPrompts.takeIdle(now: t), isNull);
      // Install day had the onboarding paywall: nothing more that day.
      expect(await ProPrompts.takeIdle(now: DateTime(2026, 10, 4, 21)), isNull);
      for (var day = 5; day <= 10; day++) {
        expect(
          await ProPrompts.takeIdle(now: DateTime(2026, 10, day, 8)),
          ProPrompts.firstWeek,
          reason: 'day $day',
        );
        // Once a day, however many visits.
        expect(
          await ProPrompts.takeIdle(now: DateTime(2026, 10, day, 20)),
          isNull,
        );
      }
      expectLogged('billing.prompt.shown', fields: {'trigger': 'first_week'});
      // Week over: weekly, counted from the last prompt.
      final week = t.add(ProPrompts.weeklyEvery);
      expect(await ProPrompts.takeIdle(now: week), isNull);
      final next = DateTime(2026, 10, 17, 8);
      expect(await ProPrompts.takeIdle(now: next), ProPrompts.weekly);
      expect(
        await ProPrompts.takeIdle(now: next.add(const Duration(days: 6))),
        isNull,
      );
      expect(
        await ProPrompts.takeIdle(now: next.add(ProPrompts.weeklyEvery)),
        ProPrompts.weekly,
      );
      // A clock set back is "too soon".
      expect(await ProPrompts.takeIdle(now: t), isNull);
    });

    test('a queued moment blocked by cooldown still lets the daily one show',
        () async {
      final t = DateTime(2026, 10, 4, 9);
      expect(await ProPrompts.takeIdle(now: t), isNull);
      expect(
        await ProPrompts.takeIdle(now: DateTime(2026, 10, 5, 9)),
        ProPrompts.firstWeek,
      );
      await ProPrompts.queue(ProPrompts.uncertain);
      expect(
        await ProPrompts.takeIdle(now: DateTime(2026, 10, 6, 9)),
        ProPrompts.firstWeek,
      );
    });

    test('a queued moment goes before the weekly prompt', () async {
      final t = DateTime(2026, 10, 4, 9);
      expect(await ProPrompts.takeIdle(now: t), isNull);
      await ProPrompts.queue(ProPrompts.uncertain);
      expect(
        await ProPrompts.takeIdle(now: t.add(const Duration(days: 8))),
        ProPrompts.uncertain,
      );
      // Shares the 3-day cooldown with the moment just shown.
      expect(
        await ProPrompts.takeIdle(now: t.add(const Duration(days: 9))),
        isNull,
      );
    });

    test('low-supply card dismissal lasts one low episode', () async {
      await ProPrompts.dismissLow('apoquel');
      expect(await ProPrompts.lowDismissed({'apoquel'}), {'apoquel'});
      // Refilled (no longer low) → forgotten; the next low episode shows it.
      expect(await ProPrompts.lowDismissed(const {}), isEmpty);
      expect(await ProPrompts.lowDismissed({'apoquel'}), isEmpty);
    });

    test('every paywall moment has its own copy and round-trips', () {
      for (final reason in PaywallReason.values) {
        expect(PaywallReasonQuery.fromQuery(reason.queryValue), reason);
        expect(reason.copy.$1, isNotEmpty);
      }
    });
  });

  group('paywall at every Pro moment', () {
    testWidgets('free: every Pro action shows a visible lock; Pro: none', (t) async {
      final care = CareRepository.sample(clock: () => DateTime(2026, 10, 3, 14));
      final router = await _pump(t, care);
      router.go(AppRoutes.household);
      await t.pumpAndSettle();
      await _reveal(t, find.text('Invite someone'));
      expect(
        find.ancestor(of: find.text('Invite someone'), matching: find.byType(WithProLock)),
        findsOneWidget,
      );
      expect(find.byType(ProLock), findsWidgets);
      router.go(AppRoutes.reports);
      await t.pumpAndSettle();
      await _reveal(t, find.text('Share with vet'));
      expect(
        find.ancestor(of: find.text('Share with vet'), matching: find.byType(WithProLock)),
        findsOneWidget,
      );
      expect(find.byType(ProLock), findsWidgets);
      router.go(AppRoutes.pets);
      await t.pumpAndSettle();
      final addPet = find.byTooltip('Add pet');
      expect(
        t.widget<Badge>(find.descendant(of: addPet, matching: find.byType(Badge))).isLabelVisible,
        isTrue,
      );

      care.debugStorePro = true;
      care.dayChanged(); // notify
      await t.pumpAndSettle();
      expect(
        t.widget<Badge>(find.descendant(of: addPet, matching: find.byType(Badge))).isLabelVisible,
        isFalse,
      );
      router.go(AppRoutes.household);
      await t.pumpAndSettle();
      expect(find.byType(ProLock), findsNothing);
    });

    testWidgets('second pet from Today opens the "every pet" paywall', (t) async {
      final care = CareRepository.sample(clock: () => DateTime(2026, 10, 3, 14));
      final router = await _pump(t, care);
      router.go(AppRoutes.pets);
      await t.pumpAndSettle();
      await t.tap(find.byTooltip('Add pet'));
      await t.pumpAndSettle();
      expect(find.text('Every pet deserves the same care'), findsOneWidget);
      expectLogged('billing.paywall.opened', fields: {'reason': 'second_pet'});
    });

    testWidgets('Free at the medicine cap: add medicine opens the paywall', (
      t,
    ) async {
      final care = CareRepository.sample(
        clock: () => DateTime(2026, 10, 3, 14),
      );
      expect(care.canAddMedication('miso'), isFalse);
      final before = care.medications.length;
      final router = await _pump(t, care);
      router.go('${AppRoutes.schedule}?pet=miso');
      await t.pumpAndSettle();
      expect(find.text('Every medicine, one schedule'), findsOneWidget);
      expectLogged('billing.paywall.opened', fields: {'reason': 'more_meds'});
      // The repository refuses too, whatever screen calls it.
      final saved = await care.addMedication(
        petId: 'miso',
        name: 'Thyroid',
        amount: '',
        parts: [DayPart.morning],
      );
      expect(saved, isFalse);
      expect(care.medications.length, before);
      expectLogged('medication.add.blocked', fields: {'reason': 'free_tier'});
      // Logging the doses already on the schedule stays free.
      expect(care.doses.where((d) => d.petId == 'miso'), isNotEmpty);
    });

    testWidgets(
      'free + running low: a dismissible card that opens the refill paywall',
      (t) async {
        // Added while Pro, then lapsed: Free over the medicine cap keeps
        // every medicine and its doses — only adding more is gated.
        final care = CareRepository.sample(
          clock: () => DateTime(2026, 10, 3, 14),
        )..debugStorePro = true;
        await care.addMedication(
          petId: 'miso',
          name: 'Apoquel',
          amount: '',
          parts: [DayPart.evening],
          supplyTotal: 3,
        );
        care.debugStorePro = false;
        final router = await _pump(t, care);
        final card = find.textContaining('Apoquel is running low');
        await _reveal(t, card);
        expect(
          find.text('Pro sends a heads-up before it runs out.'),
          findsOneWidget,
        );
        expectLogged('billing.low_supply_teaser.shown');
        await t.tap(find.text('See Pro'));
        await t.pumpAndSettle();
        expect(find.text('Never run out on a Sunday night'), findsOneWidget);
        expectLogged('billing.paywall.opened', fields: {'reason': 'refill'});
        router.go(AppRoutes.today);
        await t.pumpAndSettle();
        await _reveal(t, card);
        await t.tap(find.byTooltip('Hide'));
        await t.pumpAndSettle();
        expect(card, findsNothing);
        expectLogged('billing.low_supply_teaser.dismissed');
      },
    );

    testWidgets('Pro sees the real low-supply banner, never the teaser', (
      t,
    ) async {
      final care = CareRepository.sample(clock: () => DateTime(2026, 10, 3, 14))
        ..debugStorePro = true;
      await care.addMedication(
        petId: 'miso',
        name: 'Apoquel',
        amount: '',
        parts: [DayPart.evening],
        supplyTotal: 3,
      );
      await _pump(t, care);
      expect(find.textContaining('is running low'), findsNothing);
      expect(find.text('Apoquel: 3 doses left'), findsOneWidget);
    });

    testWidgets('"Not sure if given" never interrupts: queued, shown on the next idle visit', (t) async {
      final care = CareRepository.sample(clock: () => DateTime(2026, 10, 3, 14));
      await _pump(t, care);
      await _reveal(t, find.text('Log dose'));
      await t.tap(find.text('Log dose'));
      await t.pumpAndSettle();
      await t.tap(find.text('Not sure if given'));
      await t.pumpAndSettle(const Duration(seconds: 2));
      // Right after the care flow: no paywall, the person keeps going.
      await t.pump(const Duration(seconds: 5));
      await t.pumpAndSettle();
      expect(find.text('Not sure if it was given?'), findsNothing);
      expect(find.text('Needs a check'), findsOneWidget);
      expectLogged('billing.prompt.queued', fields: {'trigger': 'uncertain'});
      expectNotLogged('billing.paywall.opened');
      expect(
        care.loggedDose('fluids.afternoon', '2026-10-03')?.outcome,
        LogOutcome.uncertain,
      );

      // Back to the app later, idle on Today with nothing to give.
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await t.pump(const Duration(seconds: 4));
      await t.pumpAndSettle();
      expect(find.text('Not sure if it was given?'), findsOneWidget);
      expectLogged('billing.paywall.opened', fields: {'reason': 'uncertain'});
      expectLogged('billing.prompt.shown', fields: {'trigger': 'uncertain'});
    });

    testWidgets('a due dose blocks the idle prompt (safety first)', (t) async {
      SharedPreferences.setMockInitialValues({
        'pro_prompts_pending_v1': ['uncertain'],
      });
      // 2 PM: Fluids is due and not given.
      final care = CareRepository.sample(clock: () => DateTime(2026, 10, 3, 14));
      await _pump(t, care);
      await t.pump(const Duration(seconds: 4));
      await t.pumpAndSettle();
      expect(find.text('Not sure if it was given?'), findsNothing);
      expectNotLogged('billing.prompt.shown');
    });
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
