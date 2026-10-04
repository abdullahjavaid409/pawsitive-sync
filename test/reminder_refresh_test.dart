import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pawsitive_sync/core/format/clock_format.dart';
import 'package:pawsitive_sync/core/logging/app_log.dart';
import 'package:pawsitive_sync/data/care_repository.dart';
import 'package:pawsitive_sync/data/dose_reminders.dart';
import 'package:pawsitive_sync/data/household_store.dart';
import 'package:pawsitive_sync/data/push_service.dart';
import 'package:pawsitive_sync/data/reminders/reminder_background.dart';
import 'package:pawsitive_sync/data/reminders/reminder_plan.dart';
import 'package:pawsitive_sync/data/reminders/reminder_platform.dart';
import 'package:pawsitive_sync/data/reminders/reminder_settings.dart';
import 'package:pawsitive_sync/domain/models.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_household_api.dart';
import 'fake_reminder_platform.dart';
import 'test_log_helpers.dart';
import 'support/sample_household.dart';

const _today = '2026-10-04';

/// Sample household (UTC clock + zone): morning doses logged; Fluids at
/// 1 PM. Adding Gaba at 1 PM makes a two-dose group today.
Future<(CareRepository, DateTime Function(), void Function(DateTime))> _care(
  DateTime at, {
  bool gaba = true,
}) async {
  var now = at;
  final care = sampleCare(clock: () => now);
  if (gaba) {
    // Pro for setup only: Free schedules one morning medicine per pet.
    care.debugStorePro = true;
    await care.addMedication(
      petId: 'juniper',
      name: 'Gaba',
      amount: '50 mg',
      parts: [DayPart.afternoon],
    );
    care.debugStorePro = false;
  }
  return (care, () => now, (DateTime next) => now = next);
}

String _gabaDose(CareRepository care) =>
    '${care.medications.firstWhere((m) => m.name == 'Gaba').id}.afternoon';

int _groupId(ReminderKind kind, [String day = _today, int minute = 13 * 60]) =>
    ReminderIds.of(kind, 'g|$day|$minute');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakeReminderPlatform fake;

  setUp(() {
    SharedPreferences.setMockInitialValues({'reminders_on': true});
    AppLog.enableTestCapture();
    fake = FakeReminderPlatform();
    DoseReminders.platform = fake;
  });

  tearDown(() {
    DoseReminders.resetForTest();
    ClockFormat.resetForTest();
    AppLog.disableTestCapture();
  });

  group('grouped notifications on the device', () {
    test('logging one dose turns the group into the remaining dose', () async {
      final (care, _, _) = await _care(DateTime.utc(2026, 10, 4, 7));
      DoseReminders.attach(care);
      await DoseReminders.reschedule(care);
      final group = fake.scheduled[_groupId(ReminderKind.dose)]!;
      expect(group.title, '2 doses due · 1:00 PM');
      expect(group.body, 'Miso: Fluids · Juniper: Gaba');
      expect(
        fake.scheduled.containsKey(
          ReminderIds.forDose(ReminderKind.dose, 'fluids.afternoon', _today),
        ),
        isFalse,
        reason: 'no separate per-dose notification on top of the group',
      );
      expectLogged('reminders.scheduled', fields: {'trigger': 'manual'});

      await care.logDose(
        doseId: 'fluids.afternoon',
        memberId: 'you',
        amount: '',
        timeLabel: '7:01 AM',
      );
      await Future<void>.delayed(const Duration(milliseconds: 600));
      expect(fake.scheduled.containsKey(_groupId(ReminderKind.dose)), isFalse);
      expect(fake.scheduled.containsKey(_groupId(ReminderKind.followUp)), isFalse);
      final gaba = fake.scheduled[
          ReminderIds.forDose(ReminderKind.dose, _gabaDose(care), _today)]!;
      expect(gaba.title, "Juniper's Gaba · 1:00 PM");
      expect(gaba.isGroup, isFalse);
    });

    test('a push from another phone shrinks a pending group with no data loaded', () async {
      final (care, _, _) = await _care(DateTime.utc(2026, 10, 4, 7));
      await DoseReminders.reschedule(care);
      expect(fake.scheduled.containsKey(_groupId(ReminderKind.dose)), isTrue);
      await DoseReminders.cancelForDoses(const [
        PushDose(
          medicationId: 'fluids',
          part: 'afternoon',
          day: _today,
          outcome: 'given',
        ),
      ]);
      expect(fake.scheduled.containsKey(_groupId(ReminderKind.dose)), isFalse);
      final gabaId = ReminderIds.forDose(ReminderKind.dose, _gabaDose(care), _today);
      expect(fake.scheduled[gabaId]!.title, "Juniper's Gaba · 1:00 PM");
      // Reminder + follow-up group, both rebuilt with the one dose left.
      expectLogged('reminders.group_shrunk', fields: {'kept': 2, 'removed': 0, 'from': 'push'});
      // The same instant as before (rebuilt from the payload).
      expect(
        fake.scheduled[gabaId]!.when.millisecondsSinceEpoch,
        DateTime.utc(2026, 10, 4, 13).millisecondsSinceEpoch,
      );
      // The next foreground plan agrees (resolved key kept until sync).
      await DoseReminders.reschedule(care, reason: 'resume');
      expect(fake.scheduled.containsKey(_groupId(ReminderKind.dose)), isFalse);
      expect(fake.scheduled.containsKey(gabaId), isTrue);
    });

    test('"Snooze 15 min" on a group snoozes every dose once, no follow-ups', () async {
      final (care, _, _) = await _care(DateTime.utc(2026, 10, 4, 13, 5));
      await DoseReminders.reschedule(care);
      final follow = fake.scheduled[_groupId(ReminderKind.followUp)]!;
      expect(follow.title, 'Still due: 2 doses from 1:00 PM');
      final source = ReminderPayload.decode(follow.payload)!;
      expect(
        await ReminderSnooze.apply(fake, source, now: DateTime.utc(2026, 10, 4, 13, 31)),
        isTrue,
      );
      final snooze = fake.scheduled[_groupId(ReminderKind.snooze)]!;
      expect(snooze.title, '2 doses due · 1:00 PM');
      expect(snooze.body, 'Snoozed · Miso: Fluids · Juniper: Gaba');
      expect(fake.scheduled.containsKey(_groupId(ReminderKind.followUp)), isFalse);
      final snoozed = await ReminderSnooze.read();
      expect(snoozed, containsAll(['fluids.afternoon|$_today', '${_gabaDose(care)}|$_today']));

      // One dose given → the snooze keeps only the other one.
      await care.logDose(
        doseId: 'fluids.afternoon',
        memberId: 'you',
        amount: '',
        timeLabel: '1:32 PM',
      );
      await DoseReminders.reschedule(care, reason: 'data');
      expect(fake.scheduled.containsKey(_groupId(ReminderKind.snooze)), isFalse);
      expectLogged('reminders.group_shrunk', fields: {'from': 'snooze', 'kept': 1});
      final gabaSnooze = fake.scheduled[
          ReminderIds.forDose(ReminderKind.snooze, _gabaDose(care), _today)]!;
      expect(gabaSnooze.title, "Juniper's Gaba · 1:00 PM");
      expect(
        fake.ofKind(ReminderKind.followUp).where(
          (n) => n.day == _today && n.when.hour == 13,
        ),
        isEmpty,
        reason: 'no follow-up for the snoozed doses (8 PM insulin keeps its own)',
      );
    });

    test('a group tap or "Open" opens Today; an old one says so', () async {
      final (care, _, _) = await _care(DateTime.utc(2026, 10, 4, 7));
      DoseReminders.attach(care);
      await DoseReminders.reschedule(care);
      final group = fake.scheduled[_groupId(ReminderKind.dose)]!;
      await DoseReminders.handleResponse(
        ReminderResponse(actionId: ReminderActions.open, payload: group.payload),
      );
      expect(DoseReminders.pendingOpen.value?.doseId, isNull);
      expect(DoseReminders.pendingOpen.value?.message, isNull);
      final stale = ReminderPayload(
        kind: ReminderKind.dose,
        day: '2026-10-03',
        group: const [
          GroupedDose(doseId: 'a.morning', petName: 'Miso', medName: 'A'),
          GroupedDose(doseId: 'b.morning', petName: 'Miso', medName: 'B'),
        ],
      ).encode();
      await DoseReminders.handleResponse(ReminderResponse(payload: stale));
      expect(DoseReminders.pendingOpen.value?.message, contains('earlier day'));
      expectLogged('reminders.tap_stale', fields: {'doses': 2, 'group': true});
    });
  });

  group('custom times end to end', () {
    test('changing a time re-plans at once (listener), today’s logged dose stays quiet', () async {
      final (care, _, _) = await _care(DateTime.utc(2026, 10, 4, 6), gaba: false);
      DoseReminders.attach(care);
      await DoseReminders.reschedule(care);
      final before = DoseReminders.signatureOf(care);
      expect(
        await care.setMedicationTimes('insulin', {
          DayPart.morning: 7 * 60,
          DayPart.evening: 19 * 60,
        }),
        isTrue,
      );
      expect(DoseReminders.signatureOf(care), isNot(before));
      await Future<void>.delayed(const Duration(milliseconds: 600));
      expectLogged('reminders.scheduled', fields: {'trigger': 'data'});
      final evening = fake.scheduled[
          ReminderIds.forDose(ReminderKind.dose, 'insulin.evening', _today)]!;
      expect(evening.when.hour, 19);
      expect(evening.title, "Miso's Insulin · 7:00 PM");
      // Morning was logged today (sample): moving it earlier adds nothing today.
      expect(
        fake.scheduled.containsKey(
          ReminderIds.forDose(ReminderKind.dose, 'insulin.morning', _today),
        ),
        isFalse,
      );
      final tomorrow = fake.scheduled.values.firstWhere(
        (n) => n.day == '2026-10-05' && n.when.hour == 7,
      );
      expect(tomorrow.title, "Miso's Insulin · 7:00 AM");
      // Today shows the custom time too.
      expect(care.doseById('insulin.evening')!.timeLabel, '7:00 PM');
      expect(care.doseById('insulin.evening')!.subtitle, 'Miso · 7:00 PM');
    });

    test('a custom evening time makes the dose due from that time on Today', () async {
      final (care, _, set) = await _care(DateTime.utc(2026, 10, 4, 14, 50), gaba: false);
      await care.setMedicationTimes('insulin', {DayPart.evening: 15 * 60});
      expect(care.doseById('insulin.evening')!.status, DoseStatus.upcoming);
      set(DateTime.utc(2026, 10, 4, 15));
      expect(care.doseById('insulin.evening')!.status, DoseStatus.due);
      expect(care.doseById('insulin.evening')!.subtitle, 'Miso · due 3:00 PM');
    });
  });

  group('signature and stale copy', () {
    test('renaming a member or toggling shared mode re-plans pending copy', () async {
      // Joined household: You + Dan; Dan wasn't sure about tonight's dose.
      final body = connectHouseholdBody(
        logs: [
          {
            'id': 'log-dan',
            'medicationId': 'insulin',
            'part': 'morning',
            'day': _today,
            'memberId': 'dan',
            'outcome': 'uncertain',
            'amount': '',
            'timeLabel': '6:01 AM',
          },
        ],
      );
      final renamed = {
        ...body,
        'members': [
          {'id': 'you', 'name': 'You', 'role': 'owner', 'isYou': true},
          {'id': 'dan', 'name': 'Daniel', 'role': 'caregiver', 'joined': true},
        ],
      };
      final solo = {
        ...body,
        'members': [
          {'id': 'you', 'name': 'You', 'role': 'owner', 'isYou': true},
        ],
      };
      // join, then the push-token registration the join kicks off.
      final adapter = FakeHouseholdAdapter([(200, body), (200, {'ok': true})]);
      final care = CareRepository(
        api: fakeHouseholdApi(adapter),
        store: HouseholdStore(),
        clock: () => DateTime.utc(2026, 10, 4, 6, 30),
      );
      expect(await care.join(code: 'ABC234', name: 'Me'), isNull);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      DoseReminders.attach(care);
      await DoseReminders.reschedule(care);
      final id = ReminderIds.forDose(ReminderKind.dose, 'insulin.morning', _today);
      expect(fake.scheduled[id]!.body, 'Dan wasn’t sure it was given — check before giving it.');

      final before = DoseReminders.signatureOf(care);
      adapter.replies
        ..clear()
        ..add((200, renamed));
      await care.sync(force: true);
      expect(DoseReminders.signatureOf(care), isNot(before));
      await Future<void>.delayed(const Duration(milliseconds: 600));
      expect(fake.scheduled[id]!.body, 'Daniel wasn’t sure it was given — check before giving it.');

      // Dan leaves: no longer shared, so "we'll let the household know" goes.
      final tomorrow = ReminderIds.forDose(ReminderKind.dose, 'insulin.morning', '2026-10-05');
      expect(fake.scheduled[tomorrow]!.body, contains('household'));
      adapter.replies
        ..clear()
        ..add((200, solo));
      await care.sync(force: true);
      await Future<void>.delayed(const Duration(milliseconds: 600));
      expect(fake.scheduled[tomorrow]!.body, '2 u. Tap Given when it’s done.');
    });

    test('clock format and settings saves are part of the signature', () async {
      final (care, _, _) = await _care(DateTime.utc(2026, 10, 4, 6), gaba: false);
      DoseReminders.attach(care);
      await DoseReminders.reschedule(care);
      final a = DoseReminders.signatureOf(care);
      ClockFormat.update(true);
      expectLogged('clock.format_changed', fields: {'use24h': true});
      final b = DoseReminders.signatureOf(care);
      expect(b, isNot(a));
      await Future<void>.delayed(const Duration(milliseconds: 600));
      expect(
        fake.ofKind(ReminderKind.dose).first.title,
        endsWith('· 13:00'),
        reason: 'pending copy rewritten for a 24-hour phone',
      );
      await ReminderSettingsStore.write(const ReminderSettings(followUp: false));
      expect(DoseReminders.signatureOf(care), isNot(b));
      await Future<void>.delayed(const Duration(milliseconds: 600));
      expect(fake.ofKind(ReminderKind.followUp), isEmpty);
    });
  });

  group('clock changes and reboot', () {
    test('clock set forward then back: nothing in the past, nothing doubled', () async {
      final (care, _, set) = await _care(DateTime.utc(2026, 10, 4, 7));
      DoseReminders.attach(care);
      await DoseReminders.reschedule(care);
      set(DateTime.utc(2026, 10, 6, 21));
      await DoseReminders.onClockChanged(care, source: 'test');
      expectLogged('reminders.clock_changed', fields: {'source': 'test'});
      expectLogged('reminders.scheduled', fields: {'trigger': 'clock_changed'});
      final now = DateTime.utc(2026, 10, 6, 21);
      for (final n in fake.scheduled.values) {
        if (n.kind == ReminderKind.weekly) continue;
        expect(n.when.isAfter(now), isTrue, reason: '${n.kind} ${n.day}');
      }
      expect(fake.scheduled.values.where((n) => n.day == '2026-10-05'), isEmpty);

      // Back to the real time: today's afternoon group comes back, once.
      set(DateTime.utc(2026, 10, 4, 7, 5));
      await DoseReminders.onClockChanged(care, source: 'test');
      final todays = fake.scheduled.values
          .where((n) => n.day == _today && n.kind == ReminderKind.dose)
          .toList();
      expect(todays.map((n) => n.id).toSet(), hasLength(todays.length));
      expect(todays.where((n) => n.isGroup), hasLength(1));
    });

    test('the native clock channel triggers a re-plan', () async {
      final (care, _, _) = await _care(DateTime.utc(2026, 10, 4, 7));
      DoseReminders.attach(care);
      DoseReminders.listenToClock();
      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
            DoseReminders.clockChannel.name,
            const StandardMethodCodec().encodeMethodCall(
              const MethodCall('changed', 'android.intent.action.TIME_SET'),
            ),
            (_) {},
          );
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expectLogged(
        'reminders.clock_changed',
        fields: {'source': 'android.intent.action.TIME_SET'},
      );
      expectLogged('reminders.scheduled', fields: {'trigger': 'clock_changed'});
    });
  });

  test('clock signals before data is loaded, or unknown ones, are logged and ignored', () async {
    DoseReminders.listenToClock();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    Future<void> send(MethodCall call) => messenger.handlePlatformMessage(
      DoseReminders.clockChannel.name,
      const StandardMethodCodec().encodeMethodCall(call),
      (_) {},
    );
    await send(const MethodCall('changed', 'ios_significant_time_change'));
    await send(const MethodCall('mystery'));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expectLogged('reminders.clock_ignored', fields: {'reason': 'not_attached'});
    expectLogged('reminders.clock_ignored', fields: {'reason': 'unknown_method', 'method': 'mystery'});
    expect(fake.scheduleCalls, 0);
  });

  group('background refresh', () {
    test('re-plans from local data with no UI; window and safety net move forward', () async {
      final (care, _, set) = await _care(DateTime.utc(2026, 10, 4, 7));
      await DoseReminders.reschedule(care);
      final firstUpkeep = fake.scheduled[ReminderPlanner.upkeepId]!;
      // Six days later, app never opened: the OS runs the refresh.
      set(DateTime.utc(2026, 10, 10, 9));
      DoseReminders.resetForTest();
      DoseReminders.platform = fake;
      expect(await ReminderBackground.run(repository: () async => care), isTrue);
      expectLogged('reminders.scheduled', fields: {'trigger': 'background', 'background': true});
      expectLogged('reminders.background_started', fields: {'task': reminderRefreshTask});
      expectLogged('reminders.background_run');
      final upkeep = fake.scheduled[ReminderPlanner.upkeepId]!;
      expect(upkeep.when.isAfter(firstUpkeep.when), isTrue);
      expect(upkeep.day, '2026-10-16');
      expect(fake.ofKind(ReminderKind.dose).last.day, '2026-10-16');
    });

    test('keeps the last foreground copy when the token is unreadable there', () async {
      // Foreground saw a shared household; the background repo is solo.
      SharedPreferences.setMockInitialValues({
        'reminders_on': true,
        'reminders_context_v1': ['1', '0'],
      });
      final (care, _, _) = await _care(DateTime.utc(2026, 10, 4, 7), gaba: false);
      expect(await ReminderBackground.run(repository: () async => care), isTrue);
      expect(
        fake.ofKind(ReminderKind.dose).first.body,
        contains('we’ll let the household know'),
      );
    });

    test('nothing scheduled to plan, or reminders off: no work, still a success', () async {
      final empty = CareRepository(clock: () => DateTime.utc(2026, 10, 4, 7));
      expect(await ReminderBackground.run(repository: () async => empty), isTrue);
      expectLogged('reminders.background_skipped', fields: {'reason': 'no_schedule'});
      expect(fake.scheduleCalls, 0);
    });

    test('a failing load reports failure to the OS, never throws', () async {
      expect(
        await ReminderBackground.run(repository: () async => throw StateError('disk')),
        isFalse,
      );
      expectLogged('reminders.background_failed');
    });
  });
}
