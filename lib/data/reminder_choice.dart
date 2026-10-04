import 'package:pawsitive_sync/core/logging/app_log.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Remembers whether the person allowed reminders. A refusal stays off.
class ReminderChoice {
  static const _key = 'reminders_on';

  static Future<bool> read() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_key) ?? false;
    } catch (error, stack) {
      AppLog.error('store.reminder_choice_failed', error, stack, {
        'op': 'read',
      });
      return false;
    }
  }

  static Future<void> clear() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_key);
    } catch (error, stack) {
      AppLog.error('store.reminder_choice_failed', error, stack, {
        'op': 'clear',
      });
    }
  }

  static Future<void> write(bool on) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_key, on);
    } catch (error, stack) {
      AppLog.error('store.reminder_choice_failed', error, stack, {
        'op': 'write',
      });
    }
  }
}
