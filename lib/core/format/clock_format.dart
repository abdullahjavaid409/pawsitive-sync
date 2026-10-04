import 'package:flutter/foundation.dart';
import 'package:pawsitive_sync/core/logging/app_log.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// How dose times are written: "7:00 AM" or "07:00", following the phone's
/// 24-hour setting.
///
/// The UI updates [use24h] from `MediaQuery.alwaysUse24HourFormat`; the value
/// is also saved so notification copy planned in a background isolate (no
/// widget tree there) matches what the app shows. Stored dose-log times
/// ("8:02 AM") are data, not display, and are never rewritten.
abstract final class ClockFormat {
  static const _prefsKey = 'clock_24h_v1';

  /// True when the phone uses a 24-hour clock. Listened to by reminders so
  /// pending notification copy is rewritten when the setting changes.
  static final ValueNotifier<bool> use24h = ValueNotifier(false);

  /// "7:00 AM" / "19:00" for [minuteOfDay] (0–1439) in the current format.
  static String label(int minuteOfDay) =>
      format(minuteOfDay, use24h: use24h.value);

  /// Pure formatter, for tests and callers with an explicit preference.
  static String format(int minuteOfDay, {required bool use24h}) {
    final m = minuteOfDay.clamp(0, 24 * 60 - 1);
    final hour = m ~/ 60;
    final minute = (m % 60).toString().padLeft(2, '0');
    if (use24h) return '${hour.toString().padLeft(2, '0')}:$minute';
    final h12 = hour % 12 == 0 ? 12 : hour % 12;
    return '$h12:$minute ${hour < 12 ? 'AM' : 'PM'}';
  }

  /// Called from the widget tree with the device setting. Saves only on a
  /// real change, so it is cheap to call on every build.
  static void update(bool value) {
    if (use24h.value == value) return;
    use24h.value = value;
    AppLog.event('clock.format_changed', {'use24h': value});
    SharedPreferences.getInstance()
        .then((prefs) => prefs.setBool(_prefsKey, value))
        .catchError((Object error, StackTrace stack) {
          // Only background copy is affected (it falls back to 12-hour).
          AppLog.error('clock.format_save_failed', error, stack);
          return false;
        });
  }

  /// Background isolates: loads the last setting the app saw.
  static Future<void> restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      use24h.value = prefs.getBool(_prefsKey) ?? use24h.value;
    } on Object catch (error, stack) {
      // Keep the default; copy is still correct, just 12-hour.
      AppLog.error('clock.format_restore_failed', error, stack);
    }
  }

  @visibleForTesting
  static void resetForTest() => use24h.value = false;
}
