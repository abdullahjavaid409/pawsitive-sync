import 'package:pawsitive_sync/core/logging/app_log.dart';
import 'package:pawsitive_sync/data/onboarding_profile.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Remembers whether setup finished so the welcome screen does not return.
class OnboardingState {
  static const _key = 'onboarding_complete';

  static Future<bool> read() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_key) ?? false;
    } catch (error, stack) {
      AppLog.error('store.onboarding_state_failed', error, stack, {
        'op': 'read',
      });
      return false;
    }
  }

  static Future<void> write(bool complete) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_key, complete);
    } catch (error, stack) {
      AppLog.error('store.onboarding_state_failed', error, stack, {
        'op': 'write',
      });
    }
  }

  static Future<void> clear() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_key);
      await OnboardingProfile.clear();
    } catch (error, stack) {
      AppLog.error('store.onboarding_state_failed', error, stack, {
        'op': 'clear',
      });
    }
  }
}
