import 'package:pawsitive_sync/data/onboarding_profile.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Remembers whether setup finished so the welcome screen does not return.
class OnboardingState {
  static const _key = 'onboarding_complete';

  static Future<bool> read() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_key) ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> write(bool complete) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_key, complete);
    } catch (_) {}
  }

  static Future<void> clear() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_key);
      await OnboardingProfile.clear();
    } catch (_) {}
  }
}
