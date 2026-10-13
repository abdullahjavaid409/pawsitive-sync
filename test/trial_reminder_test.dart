import 'package:flutter_test/flutter_test.dart';
import 'package:pawsitive_sync/core/logging/app_log.dart';
import 'package:pawsitive_sync/data/dose_reminders.dart';
import 'package:pawsitive_sync/data/revenue_cat_service.dart';
import 'package:pawsitive_sync/data/reminders/reminder_plan.dart';
import 'package:pawsitive_sync/data/reminders/trial_reminder.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_reminder_platform.dart';
import 'support/sample_household.dart';

final _now = DateTime.utc(2026, 10, 13, 12);

TrialStatus _trial(Duration left, {bool renews = true}) =>
    TrialStatus(endsAt: _now.add(left), willRenew: renews);

void main() {
  group('when to remind', () {
    test('a 7-day trial is reminded 2 days before it ends', () {
      final at = TrialReminder.remindAt(
        _trial(const Duration(days: 7)),
        now: _now,
      );
      expect(at, _now.add(const Duration(days: 5)));
    });

    test('a short trial gets a same-day notice 12 hours before', () {
      final at = TrialReminder.remindAt(
        _trial(const Duration(days: 1)),
        now: _now,
      );
      expect(at, _now.add(const Duration(hours: 12)));
    });

    test('nearly over: nothing (never a notice during the purchase)', () {
      for (final left in const [
        Duration(hours: 12, minutes: 3),
        Duration(hours: 2),
        Duration.zero,
        Duration(days: -1),
      ]) {
        expect(
          TrialReminder.remindAt(_trial(left), now: _now),
          isNull,
          reason: '$left left',
        );
      }
    });

    test('cancelled trial or no trial: nothing to warn about', () {
      expect(
        TrialReminder.remindAt(
          _trial(const Duration(days: 7), renews: false),
          now: _now,
        ),
        isNull,
      );
      expect(TrialReminder.remindAt(TrialStatus.none, now: _now), isNull);
    });

    test('paywall day matches the reminder for every trial length', () {
      expect(TrialReminder.reminderDay(7), 5);
      expect(TrialReminder.reminderDay(14), 12);
      expect(TrialReminder.reminderDay(3), 1);
      expect(TrialReminder.reminderDay(2), isNull);
      expect(TrialReminder.reminderDay(1), isNull);
      expect(TrialReminder.reminderDay(0), isNull);
      for (final days in [3, 7, 14, 30]) {
        final at = TrialReminder.remindAt(
          _trial(Duration(days: days)),
          now: _now,
        )!;
        expect(
          at.difference(_now).inDays,
          TrialReminder.reminderDay(days),
          reason: '$days-day trial',
        );
      }
    });

    test('copy names the weekday early, the time on the last day', () {
      final end = DateTime(2026, 10, 15, 20);
      final early = TrialReminder.copy(
        end,
        remindAt: end.subtract(const Duration(days: 2)),
        platformStore: 'Apple ID',
      );
      expect(early.title, 'Your Gave It Pro trial ends on Thursday');
      expect(early.body, contains('Apple ID subscriptions'));
      final late = TrialReminder.copy(
        end,
        remindAt: end.subtract(const Duration(hours: 12)),
        platformStore: 'Google Play',
      );
      expect(late.title, 'Your Gave It Pro trial ends at 8:00 PM');
      expect(late.body, contains('Google Play'));
    });
  });

  group('store status', () {
    String iso(Duration d) => _now.add(d).toIso8601String();

    test('only an active, renewing trial with an end date counts', () {
      expect(
        RevenueCatService.trialStatus(
          active: true,
          isTrial: true,
          willRenew: true,
          expirationDate: iso(const Duration(days: 7)),
        ).endsAt,
        _now.add(const Duration(days: 7)),
      );
      for (final (active, isTrial, raw) in [
        (false, true, iso(const Duration(days: 7))), // expired
        (true, false, iso(const Duration(days: 300))), // paid year
        (true, true, null), // lifetime / no end
        (true, true, 'not a date'), // corrupt
      ]) {
        expect(
          RevenueCatService.trialStatus(
            active: active,
            isTrial: isTrial,
            willRenew: true,
            expirationDate: raw,
          ),
          TrialStatus.none,
        );
      }
    });
  });

  group('scheduling', () {
    late FakeReminderPlatform fake;

    setUp(() {
      SharedPreferences.setMockInitialValues({'reminders_on': true});
      AppLog.enableTestCapture();
      fake = FakeReminderPlatform();
      DoseReminders.platform = fake;
      TrialReminder.resetForTest();
    });

    tearDown(() {
      DoseReminders.resetForTest();
      TrialReminder.resetForTest();
      AppLog.disableTestCapture();
    });

    Future<void> sync(TrialStatus status) =>
        TrialReminder.sync(status, platformStore: 'Apple ID', now: _now);

    test('schedules one notice and moves it, never duplicates', () async {
      await sync(_trial(const Duration(days: 7)));
      expect(fake.ofKind(ReminderKind.trial), hasLength(1));
      expect(
        fake.ofKind(ReminderKind.trial).single.when.toUtc(),
        _now.add(const Duration(days: 5)),
      );

      await sync(_trial(const Duration(days: 7)));
      expect(fake.scheduleCalls, 1, reason: 'unchanged status: no work');

      await sync(_trial(const Duration(days: 3)));
      expect(fake.ofKind(ReminderKind.trial), hasLength(1));
      expect(
        fake.ofKind(ReminderKind.trial).single.when.toUtc(),
        _now.add(const Duration(days: 1)),
      );
    });

    test('cancelling, converting or expiring removes the notice', () async {
      for (final next in [
        _trial(const Duration(days: 7), renews: false),
        TrialStatus.none,
      ]) {
        TrialReminder.resetForTest();
        await sync(_trial(const Duration(days: 7)));
        expect(fake.ofKind(ReminderKind.trial), hasLength(1));
        await sync(next);
        expect(fake.ofKind(ReminderKind.trial), isEmpty);
      }
    });

    test('dose reschedules never remove the trial notice', () async {
      await sync(_trial(const Duration(days: 7)));
      final care = sampleCare(clock: () => _now);
      await DoseReminders.reschedule(care);
      expect(fake.ofKind(ReminderKind.trial), hasLength(1));
      expect(fake.ofKind(ReminderKind.dose), isNotEmpty);
    });

    test('clearing every notification re-arms on the next update', () async {
      await sync(_trial(const Duration(days: 7)));
      await DoseReminders.cancel();
      expect(fake.ofKind(ReminderKind.trial), isEmpty);
      await sync(_trial(const Duration(days: 7)));
      expect(fake.ofKind(ReminderKind.trial), hasLength(1));
    });

    test('background launches leave it alone', () async {
      DoseReminders.backgroundMode = true;
      await sync(_trial(const Duration(days: 7)));
      expect(fake.scheduleCalls, 0);
    });
  });
}
