import 'package:flutter/foundation.dart';
import 'package:pawsitive_sync/core/format/clock_format.dart';
import 'package:pawsitive_sync/core/logging/app_log.dart';
import 'package:pawsitive_sync/data/dose_reminders.dart';
import 'package:pawsitive_sync/data/reminders/reminder_plan.dart';
import 'package:timezone/timezone.dart' as tz;

/// What the store says about this phone's Pro entitlement, reduced to what
/// the trial reminder needs.
@immutable
class TrialStatus {
  const TrialStatus({required this.endsAt, required this.willRenew});

  /// Not in a free trial (paid, lifetime, expired, or never subscribed).
  static const none = TrialStatus(endsAt: null, willRenew: false);

  /// When the free trial ends and billing starts; null = not in a trial.
  final DateTime? endsAt;

  /// False once the person cancels: then there is nothing to warn about.
  final bool willRenew;

  @override
  bool operator ==(Object other) =>
      other is TrialStatus &&
      other.endsAt == endsAt &&
      other.willRenew == willRenew;

  @override
  int get hashCode => Object.hash(endsAt, willRenew);
}

/// The reminder the paywall promises: one notice before a free trial turns
/// into a paid plan, so nobody is charged by surprise. Local only.
abstract final class TrialReminder {
  static final id = ReminderIds.of(ReminderKind.trial, 'trial_end');

  /// Normal lead time; the paywall timeline shows the matching day.
  static const lead = Duration(days: 2);

  /// Short or nearly-over trials still get a same-day notice.
  static const lastCall = Duration(hours: 12);

  /// Never schedule something due in the next few minutes: it would land
  /// while the person is still looking at the purchase sheet.
  static const _minAhead = Duration(minutes: 5);

  /// When to remind, or null for no reminder. Pure, unit-tested.
  static DateTime? remindAt(TrialStatus status, {required DateTime now}) {
    final end = status.endsAt;
    if (end == null || !status.willRenew) return null;
    final earliest = now.add(_minAhead);
    for (final before in const [lead, lastCall]) {
      final at = end.subtract(before);
      if (at.isAfter(earliest)) return at;
    }
    return null;
  }

  /// Day of the trial the reminder lands on, for the paywall timeline
  /// ("Day 5" of 7). Null when the trial is too short for an early notice.
  static int? reminderDay(int trialDays) {
    final day = trialDays - lead.inDays;
    return day >= 1 ? day : null;
  }

  /// Notification copy. [platformStore] is "Apple ID" or "Google Play".
  static ({String title, String body}) copy(
    DateTime end, {
    required DateTime remindAt,
    required String platformStore,
  }) {
    final left = end.difference(remindAt);
    final when = left >= const Duration(hours: 36)
        ? 'on ${_weekdays[end.weekday - 1]}'
        : 'at ${ClockFormat.label(end.hour * 60 + end.minute)}';
    return (
      title: 'Your Gave It Pro trial ends $when',
      body:
          'Keep it and your plan starts then. Not for you? Cancel anytime '
          'in your $platformStore subscriptions before it ends.',
    );
  }

  static const _weekdays = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];

  static TrialStatus? _last;

  /// Schedules, moves or cancels the one trial notice. Safe to call on
  /// every store update: it only touches the platform when the status
  /// changed. Never throws.
  static Future<void> sync(
    TrialStatus status, {
    required String platformStore,
    DateTime? now,
  }) async {
    if (DoseReminders.backgroundMode) return;
    if (status == _last) return;
    _last = status;
    try {
      await DoseReminders.cancelOne(id);
      final clock = now ?? DateTime.now();
      final at = remindAt(status, now: clock);
      final end = status.endsAt;
      if (at == null || end == null) {
        AppLog.event('trial.reminder_cleared', {
          'reason': end == null
              ? 'no_trial'
              : !status.willRenew
              ? 'cancelled'
              : 'too_late',
        });
        return;
      }
      final text = copy(
        end.toLocal(),
        remindAt: at,
        platformStore: platformStore,
      );
      await DoseReminders.scheduleOne(
        PlannedNotification(
          id: id,
          kind: ReminderKind.trial,
          when: tz.TZDateTime.from(at, tz.local),
          title: text.title,
          body: text.body,
        ),
      );
      AppLog.event('trial.reminder_scheduled', {
        'hoursBeforeEnd': end.difference(at).inHours,
      });
    } on Object catch (error, stack) {
      // Retry on the next store update instead of believing it is set.
      _last = null;
      AppLog.error('trial.reminder_failed', error, stack);
    }
  }

  /// Forget what was scheduled (all notifications were just cleared), so
  /// the next [sync] schedules again even for an unchanged status.
  static void invalidate() => _last = null;

  @visibleForTesting
  static void resetForTest() => _last = null;
}
