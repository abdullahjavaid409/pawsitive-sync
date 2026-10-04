import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pawsitive_sync/app.dart';
import 'package:pawsitive_sync/core/logging/app_log.dart';
import 'package:pawsitive_sync/data/care_repository.dart';
import 'package:pawsitive_sync/data/dose_reminders.dart';
import 'package:pawsitive_sync/data/engagement.dart';
import 'package:pawsitive_sync/data/reminders/reminder_settings.dart';
import 'package:pawsitive_sync/domain/models.dart';
import 'package:pawsitive_sync/ui/onboarding/onboarding_view_model.dart';
import 'package:pawsitive_sync/ui/settings/notification_settings.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_reminder_platform.dart';
import 'test_log_helpers.dart';

Medication _med(
  String id, {
  List<DayPart> parts = const [DayPart.morning],
  String startDay = '2026-09-25',
  String endDay = '',
  String name = 'Antibiotic',
}) => Medication(
  id: id,
  petId: 'miso',
  name: name,
  amount: '',
  parts: parts,
  supplyTotal: 0,
  dosesLeft: 0,
  startDay: startDay,
  endDay: endDay,
);

DoseRecord _log(
  String medId,
  String day, {
  DayPart part = DayPart.morning,
  String memberId = 'you',
  LogOutcome outcome = LogOutcome.given,
  String id = '',
}) => DoseRecord(
  id: id.isEmpty ? 'log-$medId-$day-${part.name}-$memberId' : id,
  medicationId: medId,
  part: part,
  day: day,
  memberId: memberId,
  outcome: outcome,
  amount: '',
  timeLabel: '8:02 AM',
);

String _day(int d) => '2026-10-${d.toString().padLeft(2, '0')}';

void main() {
  final now = DateTime(2026, 10, 4, 14);

  group('thank-you moments', () {
    ThankYou? thanks(List<DoseRecord> logs, {bool shared = true, Set<String> dismissed = const {}}) =>
        Engagement.thanks(
          logs: logs,
          today: _day(4),
          myMemberId: 'you',
          shared: shared,
          dismissed: dismissed,
          nameOf: (id) => id == 'sam' ? 'Sam' : 'You',
          medication: (id) => _med(id, name: 'Insulin'),
          pet: (_) => const Pet(
            id: 'miso',
            name: 'Miso',
            species: Species.cat,
            ageYears: 1,
            breed: '',
            sex: '',
            conditions: [],
            weightKg: 4,
            onTimePercent: 100,
            dailyMeds: 1,
          ),
        );

    test('newest dose someone else gave today', () {
      final t = thanks([
        _log('insulin', _day(4), memberId: 'sam', id: 'l2'),
        _log('insulin', _day(3), memberId: 'sam', id: 'l1'),
      ]);
      expect(t?.text, "Sam gave Miso's Insulin — thanks, Sam");
      expect(t?.logId, 'l2');
    });

    test('not for my own doses, skips, other days, solo phones, or once dismissed', () {
      expect(thanks([_log('insulin', _day(4))]), isNull);
      expect(
        thanks([_log('insulin', _day(4), memberId: 'sam', outcome: LogOutcome.skipped)]),
        isNull,
      );
      expect(thanks([_log('insulin', _day(3), memberId: 'sam')]), isNull);
      expect(thanks([_log('insulin', _day(4), memberId: 'sam')], shared: false), isNull);
      expect(
        thanks([_log('insulin', _day(4), memberId: 'sam', id: 'x')], dismissed: {'x'}),
        isNull,
      );
    });
  });

  group('course completion', () {
    List<CourseDone> courses(List<Medication> meds, List<DoseRecord> logs, {DateTime? at}) =>
        Engagement.courses(
          medications: meds,
          logs: logs,
          now: at ?? now,
          shared: true,
          dismissed: const {},
          petName: (_) => 'Miso',
        );

    final course = _med('abx', startDay: _day(1), endDay: _day(4));
    final allGiven = [for (var d = 1; d <= 4; d++) _log('abx', _day(d))];

    test('every dose given: a celebration with honest counts', () {
      final done = courses([course], allGiven).single;
      expect(done.title, 'Antibiotic course complete 🎉');
      expect(done.body, 'Miso got every dose — 4 of 4. Nice work, everyone.');
    });

    test('not until the last day’s doses are logged', () {
      expect(courses([course], allGiven.take(3).toList()), isEmpty);
    });

    test('a missed dose: "finished" with counts, no confetti, no blame', () {
      final done = courses(
        [course],
        allGiven.where((l) => l.day != _day(2)).toList(),
        at: DateTime(2026, 10, 5, 9),
      ).single;
      expect(done.title, 'Antibiotic course finished');
      expect(done.body, 'Miso got 3 of 4 doses.');
    });

    test('ongoing medicines never; old courses drop off after 3 days', () {
      expect(courses([_med('daily')], allGiven), isEmpty);
      expect(courses([course], allGiven, at: DateTime(2026, 10, 7, 9)), isEmpty);
    });
  });

  group('care count', () {
    test('counts only days where every scheduled dose was given', () {
      final days = Engagement.fullDays(
        medications: [_med('a', parts: [DayPart.morning, DayPart.evening], startDay: _day(1))],
        logs: [
          _log('a', _day(1)),
          _log('a', _day(1), part: DayPart.evening),
          _log('a', _day(2)), // evening missing
          _log('a', _day(3)),
          _log('a', _day(3), part: DayPart.evening),
        ],
        now: now,
        fromDay: '2026-09-20',
      );
      expect(days, {_day(1), _day(3)});
    });

    test('cumulative: the count never drops, even if history is later trimmed', () async {
      SharedPreferences.setMockInitialValues({});
      AppLog.enableTestCapture();
      final state = EngagementState();
      await state.load();
      final care = CareRepository.sample(clock: () => DateTime(2026, 10, 4, 21));
      for (final dose in care.doses.where((d) => d.status != DoseStatus.given)) {
        await care.logDose(doseId: dose.id, memberId: 'you', amount: '', timeLabel: '9:00 PM');
      }
      state.update(care);
      expect(state.careDayCount, 1);
      expectLogged('engagement.care_days', fields: {'count': 1});
      // A fresh load reads the saved days; a day with gaps adds nothing.
      final again = EngagementState();
      await again.load();
      again.update(CareRepository.sample(clock: () => DateTime(2026, 10, 5, 9)));
      expect(again.careDayCount, 1);
      AppLog.disableTestCapture();
    });

    test('milestone copy', () {
      expect(Engagement.milestoneText(7, 'Miso'), contains('A full week'));
      expect(Engagement.milestoneText(8, 'Miso'), isNull);
    });
  });

  group('settings', () {
    test('round-trip and junk tolerance', () {
      const s = ReminderSettings(followUp: false, quietStartMinute: 21 * 60);
      final back = ReminderSettings.fromJson(s.toJson());
      expect(back.followUp, isFalse);
      expect(back.quietStartMinute, 21 * 60);
      final junk = ReminderSettings.fromJson({'followUp': 'yes', 'quietEnd': 99999});
      expect(junk.followUp, isTrue);
      expect(junk.quietEndMinute, 7 * 60);
    });
  });

  group('UI', () {
    late FakeReminderPlatform fake;

    setUp(() {
      SharedPreferences.setMockInitialValues({'reminders_on': true});
      fake = FakeReminderPlatform();
      DoseReminders.platform = fake;
    });

    Future<EngagementState> pumpApp(WidgetTester tester, CareRepository care) async {
      tester.view.physicalSize = const Size(430, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final engagement = EngagementState();
      final onboarding = OnboardingViewModel()..finish(reminders: true);
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: care),
            ChangeNotifierProvider.value(value: onboarding),
            ChangeNotifierProvider.value(value: engagement),
          ],
          child: const PawsitiveApp(),
        ),
      );
      await tester.pumpAndSettle();
      return engagement;
    }

    testWidgets('a notification tap opens that dose’s log sheet on Today', (tester) async {
      final care = CareRepository.sample();
      await pumpApp(tester, care);
      final due = care.doses.firstWhere((d) => d.status == DoseStatus.due);
      DoseReminders.pendingOpen.value = ReminderOpen(doseId: due.id);
      await tester.pumpAndSettle();
      expect(find.text('Amount given'), findsOneWidget, reason: 'the log sheet');
      expect(DoseReminders.pendingOpen.value, isNull, reason: 'handled once');
    });

    testWidgets('reminders on but blocked by the OS: one honest note, dismissible', (tester) async {
      final care = CareRepository.sample();
      final engagement = await pumpApp(tester, care);
      DoseReminders.permission.value = ReminderPermission.denied;
      await tester.pumpAndSettle();
      final note = find.textContaining('Notifications are off for Pawsitive');
      await tester.scrollUntilVisible(note, 200, scrollable: find.byType(Scrollable).first);
      expect(note, findsOneWidget);
      await tester.tap(find.text('Not now'));
      await tester.pumpAndSettle();
      expect(note, findsNothing);
      expect(engagement.permissionNudgeHidden(care.now), isTrue);
    });

    testWidgets('Settings: each engagement feature has its own opt-out', (tester) async {
      final care = CareRepository.sample();
      final engagement = EngagementState();
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: care),
            ChangeNotifierProvider.value(value: engagement),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: NotificationSettings(
                  remindersOn: true,
                  onToggleReminders: (_) {},
                  care: care,
                ),
              ),
            ),
          ),
        ),
      );
      for (final label in [
        'Follow-up if not logged',
        'Weekly summary',
        'Refill heads-up',
        'Quiet hours',
        'Thank-you moments',
        'Care count',
      ]) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
      expect(find.text('See Pro'), findsOneWidget, reason: 'refill stays Pro');
      await tester.tap(find.text('Follow-up if not logged'));
      await tester.pumpAndSettle();
      expect(engagement.settings.followUp, isFalse);
      expect((await ReminderSettingsStore.read()).followUp, isFalse);
    });
  });
}
