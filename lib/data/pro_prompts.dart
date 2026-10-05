import 'package:pawsitive_sync/core/logging/app_log.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// When a free user may see an upgrade prompt the app opens by itself.
///
/// Tapping a Pro feature (add a second pet, invite, vet export, refill
/// alerts) always opens the paywall — that’s the person asking. Prompts
/// the app shows on its own follow two honest limits so Pro never nags:
/// each trigger at most once ever, and at most one per [cooldown].
/// Safety (logging, the double-dose check) is never interrupted: auto
/// prompts only open after a flow has finished.
///
/// One exception to "once ever": the recurring reminder on an idle visit
/// to Today — [firstWeek] once a day for the first [weeklyEvery] after
/// install (never on install day), then [weekly] once per [weeklyEvery].
abstract final class ProPrompts {
  static const _shownKey = 'pro_prompts_shown_v1';
  static const _lastKey = 'pro_prompts_last_v1';
  static const _lowDismissedKey = 'pro_prompts_low_dismissed_v1';
  static const _pendingKey = 'pro_prompts_pending_v1';
  static const _firstSeenKey = 'pro_prompts_first_seen_v1';

  /// Minimum gap between two auto prompts.
  static const cooldown = Duration(days: 3);

  /// Trigger ids (logged; never reorder meaning).
  static const uncertain = 'uncertain';

  /// Recurring idle upgrade prompt (also its paywall reason).
  static const weekly = 'weekly';

  /// Daily idle upgrade prompt in the first week (also its paywall reason).
  static const firstWeek = 'first_week';

  /// Gap between two [weekly] prompts, and the quiet start after install.
  static const weeklyEvery = Duration(days: 7);

  /// True (and recorded) when [trigger] may auto-open now. Logs either
  /// `billing.prompt.shown` or `billing.prompt.suppressed` with the reason.
  static Future<bool> tryAuto(String trigger, {required DateTime now}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final shown = {...?prefs.getStringList(_shownKey)};
      if (shown.contains(trigger)) {
        AppLog.event('billing.prompt.suppressed', {
          'trigger': trigger,
          'reason': 'already_shown',
        });
        return false;
      }
      final last = prefs.getInt(_lastKey);
      if (last != null) {
        final since = now.difference(DateTime.fromMillisecondsSinceEpoch(last));
        // A clock set back counts as "too soon", never as a free pass.
        if (since < cooldown) {
          AppLog.event('billing.prompt.suppressed', {
            'trigger': trigger,
            'reason': 'cooldown',
          });
          return false;
        }
      }
      await prefs.setStringList(_shownKey, [...shown, trigger]);
      await prefs.setInt(_lastKey, now.millisecondsSinceEpoch);
      AppLog.event('billing.prompt.shown', {'trigger': trigger});
      return true;
    } on Object catch (error, stack) {
      // Unsure → don’t interrupt. The tap-to-upgrade paths still work.
      AppLog.error('billing.prompt_failed', error, stack);
      return false;
    }
  }

  /// Remembers [trigger] for later instead of showing it now: the moment
  /// happened inside a care flow, which must never be interrupted. Shown
  /// by [takeIdle] when the person is next idle on Today.
  static Future<void> queue(String trigger) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if ({...?prefs.getStringList(_shownKey)}.contains(trigger)) return;
      final pending = {...?prefs.getStringList(_pendingKey)};
      if (!pending.add(trigger)) return;
      await prefs.setStringList(_pendingKey, pending.toList());
      AppLog.event('billing.prompt.queued', {'trigger': trigger});
    } on Object catch (error, stack) {
      AppLog.error('billing.prompt_failed', error, stack, {'op': 'queue'});
    }
  }

  /// The trigger to show now: a queued moment first (passing [tryAuto]'s
  /// limits; left queued when only the cooldown blocks it), else the
  /// recurring reminder when it’s due. Null when nothing is due.
  static Future<String?> takeIdle({required DateTime now}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final pending = [...?prefs.getStringList(_pendingKey)];
      if (pending.isNotEmpty) {
        final trigger = pending.first;
        final shown = await tryAuto(trigger, now: now);
        final alreadyShown = {...?prefs.getStringList(_shownKey)}
            .contains(trigger);
        if (shown || alreadyShown) {
          await prefs.setStringList(_pendingKey, pending.skip(1).toList());
        }
        if (shown) return trigger;
      }
      return await _takeRecurring(prefs, now);
    } on Object catch (error, stack) {
      AppLog.error('billing.prompt_failed', error, stack, {'op': 'take'});
      return null;
    }
  }

  /// [firstWeek] or [weekly] when it’s due, else null. The first call
  /// only records when the app was first seen.
  static Future<String?> _takeRecurring(
    SharedPreferences prefs,
    DateTime now,
  ) async {
    final first = prefs.getInt(_firstSeenKey);
    if (first == null) {
      await prefs.setInt(_firstSeenKey, now.millisecondsSinceEpoch);
      return null;
    }
    final firstSeen = DateTime.fromMillisecondsSinceEpoch(first);
    final last = prefs.getInt(_lastKey);
    final lastShown = last == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(last);
    // A clock set back counts as "too soon", never as a free pass.
    if (now.isBefore(firstSeen) ||
        (lastShown != null && now.isBefore(lastShown))) {
      return null;
    }
    final String trigger;
    if (now.difference(firstSeen) < weeklyEvery) {
      // First week: once per calendar day, never on install day (that
      // day already had the onboarding paywall).
      if (_sameDay(now, firstSeen)) return null;
      if (lastShown != null && _sameDay(now, lastShown)) return null;
      trigger = firstWeek;
    } else {
      if (lastShown != null && now.difference(lastShown) < weeklyEvery) {
        return null;
      }
      trigger = weekly;
    }
    await prefs.setInt(_lastKey, now.millisecondsSinceEpoch);
    AppLog.event('billing.prompt.shown', {'trigger': trigger});
    return trigger;
  }

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  /// Medicines whose free low-supply card was dismissed. Ids that are no
  /// longer low are dropped, so the next low episode shows the card again.
  static Future<Set<String>> lowDismissed(Set<String> lowNow) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = {...?prefs.getStringList(_lowDismissedKey)};
      final keep = saved.intersection(lowNow);
      if (keep.length != saved.length) {
        await prefs.setStringList(_lowDismissedKey, keep.toList());
      }
      return keep;
    } on Object catch (error, stack) {
      AppLog.error('billing.prompt_failed', error, stack, {'op': 'low_read'});
      return const {};
    }
  }

  /// Hides the free low-supply card for [medicationId] this episode.
  static Future<void> dismissLow(String medicationId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(
        _lowDismissedKey,
        {...?prefs.getStringList(_lowDismissedKey), medicationId}.toList(),
      );
      AppLog.event('billing.low_supply_teaser.dismissed', {
        'medicationId': medicationId,
      });
    } on Object catch (error, stack) {
      AppLog.error('billing.prompt_failed', error, stack, {
        'op': 'low_dismiss',
      });
    }
  }
}
