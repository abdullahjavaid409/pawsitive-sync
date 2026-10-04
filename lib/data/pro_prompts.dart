import 'package:pawsitive_sync/core/logging/app_log.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// When a free user may see an upgrade prompt the app opens by itself.
///
/// Tapping a Pro feature (add a second pet, invite, vet export, refill
/// alerts) always opens the paywall — that's the person asking. Prompts
/// the app shows on its own follow two honest limits so Pro never nags:
/// each trigger at most once ever, and at most one per [cooldown].
/// Safety (logging, the double-dose check) is never interrupted: auto
/// prompts only open after a flow has finished.
abstract final class ProPrompts {
  static const _shownKey = 'pro_prompts_shown_v1';
  static const _lastKey = 'pro_prompts_last_v1';
  static const _lowDismissedKey = 'pro_prompts_low_dismissed_v1';
  static const _pendingKey = 'pro_prompts_pending_v1';

  /// Minimum gap between two auto prompts.
  static const cooldown = Duration(days: 3);

  /// Trigger ids (logged; never reorder meaning).
  static const uncertain = 'uncertain';

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
        final since = now.difference(
          DateTime.fromMillisecondsSinceEpoch(last),
        );
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
      // Unsure → don't interrupt. The tap-to-upgrade paths still work.
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

  /// The queued trigger to show now (passing [tryAuto]'s limits), or null.
  /// Leaves it queued when only the cooldown blocks it.
  static Future<String?> takeIdle({required DateTime now}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final pending = [...?prefs.getStringList(_pendingKey)];
      if (pending.isEmpty) return null;
      final trigger = pending.first;
      final shown = await tryAuto(trigger, now: now);
      final alreadyShown = {...?prefs.getStringList(_shownKey)}.contains(trigger);
      if (shown || alreadyShown) {
        await prefs.setStringList(_pendingKey, pending.skip(1).toList());
      }
      return shown ? trigger : null;
    } on Object catch (error, stack) {
      AppLog.error('billing.prompt_failed', error, stack, {'op': 'take'});
      return null;
    }
  }

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
      await prefs.setStringList(_lowDismissedKey, {
        ...?prefs.getStringList(_lowDismissedKey),
        medicationId,
      }.toList());
      AppLog.event('billing.low_supply_teaser.dismissed', {
        'medicationId': medicationId,
      });
    } on Object catch (error, stack) {
      AppLog.error('billing.prompt_failed', error, stack, {'op': 'low_dismiss'});
    }
  }
}
