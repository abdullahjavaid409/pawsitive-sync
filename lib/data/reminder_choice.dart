import 'package:shared_preferences/shared_preferences.dart';

/// Remembers whether the person allowed reminders. A refusal stays off.
class ReminderChoice {
  static const _key = 'reminders_on';

  static Future<bool> read() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_key) ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> write(bool on) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_key, on);
    } catch (_) {}
  }
}
