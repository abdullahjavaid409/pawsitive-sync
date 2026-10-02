import 'package:shared_preferences/shared_preferences.dart';

/// Persists dismiss for the post-value Pro nudge on Today.
abstract final class UpgradeNudgeState {
  static const _dismissedKey = 'upgrade_nudge_dismissed_v1';
  static const minGivenDoses = 5;

  static Future<bool> isDismissed() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_dismissedKey) ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> dismiss() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_dismissedKey, true);
    } catch (_) {}
  }

  static Future<void> clear() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_dismissedKey);
    } catch (_) {}
  }
}
