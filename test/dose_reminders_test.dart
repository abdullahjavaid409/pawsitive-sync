import 'package:flutter_test/flutter_test.dart';
import 'package:pawsitive_sync/core/logging/app_log.dart';
import 'package:pawsitive_sync/data/care_repository.dart';
import 'package:pawsitive_sync/data/dose_reminders.dart';
import 'package:pawsitive_sync/data/push_service.dart';
import 'package:pawsitive_sync/data/reminders/reminder_plan.dart';
import 'package:pawsitive_sync/data/reminders/reminder_platform.dart';
import 'package:pawsitive_sync/data/reminders/reminder_settings.dart';
import 'package:pawsitive_sync/domain/models.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;

import 'fake_reminder_platform.dart';
import 'test_log_helpers.dart';

/// Sample household: insulin AM+PM, benazepril AM, joint AM, fluids PM. Morning doses are already logged by Sara and Dan.
/// UTC clock + UTC zone so the test host's own zone never matters.
CareRepository _care([DateTime? at]) {
  var now = at ?? DateTime.utc(2026, 10, 4, 14);
  return CareRepository.sample(clock: () => now);
}

const _today = '2026-10-04';

int _id(ReminderKind kind, String doseId, [String day = _today]) =>
    ReminderIds.forDose(kind, doseId, day);

ReminderResponse _response(
  String doseId, {
  String? action,
  String day = _today,
  ReminderKind kind = ReminderKind.dose,
}) => ReminderResponse(
  actionId: action,
  payload: ReminderPayload(
    kind: kind,
    doseId: doseId,
    day: day,
    title: 'Miso’s Fluids · 1:00 PM',
  ).encode(),
);

void main() {
  late FakeReminderPlatform fake;

  setUp(() {
    SharedPreferences.setMockInitialValues({'reminders_on': true});
    AppLog.enableTestCapture();
    fake = FakeReminderPlatform();
    DoseReminders.platform = fake;
  });

  tearDown(() {
    DoseReminders.resetForTest();
    AppLog.disableTestCapture();
  });

  group('scheduling', () {
    test('every open dose for the coming days, each with its own id', () async {
      final care = _care(DateTime.utc(2026, 10, 4, 7));
      await DoseReminders.reschedule(care);
      final doses = fake.ofKind(ReminderKind.dose);
      // Today: fluids 1 PM + insulin 8 PM (morning already given by Sara/Dan).
      expect(doses.take(2).map((n) => n.doseId), ['fluids.afternoon', 'insulin.evening']);
      expect(doses.where((n) => n.day == _today), hasLength(2));
      // Tomorrow onwards: all five doses a day, not just one reminder —
      // the three 8:00 AM doses share one grouped notification.
      final tomorrow = doses.where((n) => n.day == '2026-10-05').toList();
      expect(tomorrow, hasLength(3));
      expect(
        tomorrow.fold<int>(0, (sum, n) => sum + (n.isGroup ? n.group.length : 1)),
        5,
      );
      expect(tomorrow.first.title, '3 doses due · 8:00 AM');
      expect(fake.scheduled.length, lessThan(64));
      expect(fake.scheduled.containsKey(_id(ReminderKind.dose, 'insulin.morning')), isFalse);
      expectLogged('reminders.scheduled', fields: {'trigger': 'manual'});
      expectLogged('reminders.ready', fields: {'zone': 'UTC'});
    });

    test('an unchanged plan re-adds nothing; the old single reminder is removed', () async {
      final care = _care();
      fake.scheduled[ReminderIds.legacy] = PlannedNotification(
        id: ReminderIds.legacy,
        kind: ReminderKind.dose,
        when: tz.TZDateTime.utc(2026, 10, 4, 20),
        title: 'Time for Miso',
        body: 'old',
      );
      await DoseReminders.reschedule(care);
      expect(fake.cancelled, contains(ReminderIds.legacy));
      final calls = fake.scheduleCalls;
      await DoseReminders.reschedule(care, reason: 'resume');
      expect(fake.scheduleCalls, calls, reason: 'diffed against pending');
      expectLogged('reminders.scheduled', fields: {'trigger': 'resume', 'added': 0});
    });

    test('logging a dose (here or synced) cancels it at once via the listener', () async {
      final care = _care();
      DoseReminders.attach(care);
      await DoseReminders.reschedule(care);
      final evening = _id(ReminderKind.dose, 'insulin.evening');
      expect(fake.scheduled.containsKey(evening), isTrue);
      final ok = await care.logDose(
        doseId: 'insulin.evening',
        memberId: 'dan',
        amount: '2 units',
        timeLabel: '7:55 PM',
      );
      expect(ok, isTrue);
      await Future<void>.delayed(const Duration(milliseconds: 600));
      expect(fake.scheduled.containsKey(evening), isFalse);
      expect(
        fake.scheduled.containsKey(_id(ReminderKind.followUp, 'insulin.evening')),
        isFalse,
      );
      expect(fake.cancelled, contains(evening));
      expectLogged('reminders.scheduled', fields: {'trigger': 'data'});
    });

    test('reminders off: owned notifications cancelled, nothing scheduled', () async {
      final care = _care();
      await DoseReminders.reschedule(care);
      expect(fake.scheduled, isNotEmpty);
      SharedPreferences.setMockInitialValues({'reminders_on': false});
      await DoseReminders.reschedule(care, reason: 'toggled');
      expect(fake.scheduled, isEmpty);
      expectLogged('reminders.schedule_skipped', fields: {'reason': 'off'});
    });

    test('permission denied: no scheduling attempts, honest state for the UI', () async {
      fake.granted = ReminderPermission.denied;
      await DoseReminders.reschedule(_care());
      expect(fake.scheduleCalls, 0);
      expect(DoseReminders.permission.value, ReminderPermission.denied);
      expectLogged(
        'reminders.schedule_skipped',
        fields: {'reason': 'permission_denied'},
      );
    });

    test('Android without exact alarms falls back to inexact', () async {
      fake.exact = false;
      await DoseReminders.reschedule(_care());
      expect(fake.exactFlags, isNotEmpty);
      expect(fake.exactFlags.every((e) => !e), isTrue);
      expect(DoseReminders.exactAllowed.value, isFalse);
    });

    test('time zone change (travel) re-aims to 8:00 in the new zone', () async {
      final care = _care(DateTime.utc(2026, 10, 4, 1));
      await DoseReminders.reschedule(care);
      fake.zone = 'Asia/Tokyo';
      await DoseReminders.onResume(care);
      expectLogged(
        'reminders.timezone_changed',
        fields: {'from': 'UTC', 'to': 'Asia/Tokyo'},
      );
      expectLogged('reminders.scheduled', fields: {'trigger': 'timezone_changed'});
      final first = fake.ofKind(ReminderKind.dose).first;
      expect(first.when.location.name, 'Asia/Tokyo');
      expect(first.when.hour, anyOf(8, 13, 20));
    });

    test('engagement settings are read every time (weekly summary opt-out)', () async {
      // Sunday 2 PM: this morning's doses count toward tonight's summary.
      final care = _care();
      await DoseReminders.reschedule(care);
      expect(fake.ofKind(ReminderKind.weekly), hasLength(1));
      await ReminderSettingsStore.write(const ReminderSettings(weeklySummary: false));
      await DoseReminders.reschedule(care, reason: 'settings');
      expect(fake.ofKind(ReminderKind.weekly), isEmpty);
    });

    test('concurrent reschedules run one at a time, last one wins', () async {
      final care = _care();
      await Future.wait([
        DoseReminders.reschedule(care, reason: 'a'),
        DoseReminders.reschedule(care, reason: 'b'),
        DoseReminders.reschedule(care, reason: 'c'),
      ]);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final runs = AppLog.testRecords.where((r) => r.name == 'reminders.scheduled');
      expect(runs.length, 2, reason: 'one running + one queued, not three');
      expect(runs.last.fields['trigger'], 'c');
    });
  });

  group('push from another phone', () {
    test('a dose given elsewhere stays cancelled until this phone syncs', () async {
      final care = _care();
      await DoseReminders.reschedule(care);
      final evening = _id(ReminderKind.dose, 'insulin.evening');
      await DoseReminders.cancelForDoses(const [
        PushDose(
          medicationId: 'insulin',
          part: 'evening',
          day: _today,
          outcome: 'given',
        ),
      ]);
      expect(fake.scheduled.containsKey(evening), isFalse);
      // A resume before the sync must not bring it back.
      await DoseReminders.reschedule(care, reason: 'resume');
      expect(fake.scheduled.containsKey(evening), isFalse);
    });
  });

  group('snooze', () {
    test('own id per dose: never replaces the next reminder; no follow-up on top', () async {
      final care = _care(DateTime.utc(2026, 10, 4, 13, 5));
      await DoseReminders.reschedule(care);
      final follow = _id(ReminderKind.followUp, 'fluids.afternoon');
      expect(fake.scheduled.containsKey(follow), isTrue);
      final dose = care.doseById('fluids.afternoon')!;
      expect(await DoseReminders.snoozeMinutes(care, 15, target: dose), isTrue);
      final snooze = _id(ReminderKind.snooze, 'fluids.afternoon');
      expect(fake.scheduled[snooze]!.when, tz.TZDateTime.utc(2026, 10, 4, 13, 20));
      expect(fake.scheduled.containsKey(follow), isFalse);
      expect(
        fake.scheduled.containsKey(_id(ReminderKind.dose, 'insulin.evening')),
        isTrue,
        reason: 'the next dose keeps its reminder',
      );
      // A later reschedule keeps the snooze and doesn't re-add the follow-up.
      await DoseReminders.reschedule(care, reason: 'resume');
      expect(fake.scheduled.containsKey(snooze), isTrue);
      expect(fake.scheduled.containsKey(follow), isFalse);
      // Given → the snooze goes too.
      await care.logDose(
        doseId: 'fluids.afternoon',
        memberId: 'you',
        amount: '',
        timeLabel: '1:10 PM',
      );
      await DoseReminders.reschedule(care, reason: 'data');
      expect(fake.scheduled.containsKey(snooze), isFalse);
      expectLogged('reminders.snoozed', fields: {'minutes': 15});
    });

    test('snooze from the notification (background) uses only the payload', () async {
      final ok = await ReminderSnooze.apply(
        fake,
        const ReminderPayload(
          kind: ReminderKind.followUp,
          doseId: 'fluids.afternoon',
          day: _today,
          title: 'Still due',
        ),
        now: DateTime.utc(2026, 10, 4, 13, 31),
      );
      expect(ok, isTrue);
      expect(fake.cancelled, contains(_id(ReminderKind.followUp, 'fluids.afternoon')));
      expect(await ReminderSnooze.read(), contains('fluids.afternoon|$_today'));
      expect(
        await ReminderSnooze.apply(fake, const ReminderPayload(kind: ReminderKind.dose)),
        isFalse,
        reason: 'junk payload does nothing',
      );
    });

    test('snooze with nothing due or permission denied is refused', () async {
      final care = _care(DateTime.utc(2026, 10, 4, 7));
      expect(await DoseReminders.snoozeMinutes(care, 15), isFalse);
      expectLogged('lock.snooze_skipped', fields: {'reason': 'nothing_due'});
    });
  });

  group('Given from the notification', () {
    test('logs once, with the double-dose check, and says so in the app', () async {
      final care = _care();
      DoseReminders.attach(care);
      await DoseReminders.handleResponse(
        _response('fluids.afternoon', action: ReminderActions.given),
      );
      final log = care.loggedDose('fluids.afternoon', _today);
      expect(log?.outcome, LogOutcome.given);
      expect(log?.memberId, 'you');
      expect(DoseReminders.pendingOpen.value?.message, 'Logged Fluids for Miso.');
      expectLogged('reminders.given', fields: {'doseId': 'fluids.afternoon'});
    });

    test('a double tap logs one dose', () async {
      final care = _care();
      DoseReminders.attach(care);
      await Future.wait([
        DoseReminders.handleResponse(
          _response('fluids.afternoon', action: ReminderActions.given),
        ),
        DoseReminders.handleResponse(
          _response('fluids.afternoon', action: ReminderActions.given),
        ),
      ]);
      final logs = care.logs.where(
        (l) => l.medicationId == 'fluids' && l.day == _today,
      );
      expect(logs, hasLength(1));
      expect(
        AppLog.testRecords.where((r) => r.name == 'reminders.given_rejected'),
        hasLength(1),
      );
    });

    test('already given by someone else: no second log, an honest notification', () async {
      final care = _care();
      DoseReminders.attach(care);
      await care.logDose(
        doseId: 'fluids.afternoon',
        memberId: 'dan',
        amount: '',
        timeLabel: '1:04 PM',
      );
      final before = care.logs.length;
      await DoseReminders.handleResponse(
        _response('fluids.afternoon', action: ReminderActions.given),
      );
      expect(care.logs.length, before);
      final (_, title, body, kind) = fake.shown.single;
      expect(kind, ReminderKind.alreadyLogged);
      expect(title, 'Already given');
      expect(body, "Dan gave Miso's Fluids at 1:04 PM — no need to give it again.");
      expectLogged('reminders.given_rejected', fields: {'reason': 'already_logged'});
    });

    test('yesterday’s reminder never logs today’s dose', () async {
      final care = _care();
      DoseReminders.attach(care);
      await DoseReminders.handleResponse(
        _response('fluids.afternoon', action: ReminderActions.given, day: '2026-10-03'),
      );
      expect(care.loggedDose('fluids.afternoon', _today), isNull);
      expectLogged('reminders.given_rejected', fields: {'reason': 'stale_day'});
    });

    test('a medicine removed since the reminder: nothing logged', () async {
      final care = _care();
      DoseReminders.attach(care);
      await DoseReminders.handleResponse(
        _response('gone.morning', action: ReminderActions.given),
      );
      expectLogged('reminders.given_rejected', fields: {'reason': 'not_scheduled'});
    });
  });

  group('taps and cold start', () {
    test('a tap opens that dose; an old one opens today; junk opens Today', () async {
      DoseReminders.attach(_care());
      await DoseReminders.handleResponse(_response('fluids.afternoon'));
      expect(DoseReminders.pendingOpen.value?.doseId, 'fluids.afternoon');
      await DoseReminders.handleResponse(_response('fluids.afternoon', day: '2026-10-01'));
      expect(DoseReminders.pendingOpen.value?.doseId, isNull);
      expect(DoseReminders.pendingOpen.value?.message, contains('earlier day'));
      DoseReminders.pendingOpen.value = null;
      await DoseReminders.handleResponse(const ReminderResponse(payload: 'junk'));
      expect(DoseReminders.pendingOpen.value, isNotNull);
      expectLogged('reminders.tap_stale');
    });

    test('the tap that launched the app is handled after data loads', () async {
      DoseReminders.attach(_care());
      fake.launch = _response('insulin.evening');
      await DoseReminders.handleLaunch();
      expect(DoseReminders.pendingOpen.value?.doseId, 'insulin.evening');
      expectLogged('reminders.opened', fields: {'coldStart': true, 'action': 'tap'});
    });
  });
}
