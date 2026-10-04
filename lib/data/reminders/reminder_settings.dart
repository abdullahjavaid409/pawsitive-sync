import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:pawsitive_sync/core/logging/app_log.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The person's notification and engagement choices. Every engagement
/// feature has its own opt-out; dose reminders themselves are the master
/// switch in [ReminderChoice].
class ReminderSettings {
  const ReminderSettings({
    this.followUp = true,
    this.weeklySummary = true,
    this.thanks = true,
    this.careCount = true,
    this.refill = true,
    this.quietHours = true,
    this.quietStartMinute = 22 * 60,
    this.quietEndMinute = 7 * 60,
    this.weeklyMinute = 18 * 60,
  });

  /// One gentle "Still due" nudge ~30 min after a dose time.
  final bool followUp;

  /// Sunday local notification with the week's given/expected counts.
  final bool weeklySummary;

  /// In-app "Sam gave Miso's insulin — thanks, Sam" card.
  final bool thanks;

  /// In-app count of days with every dose given (never shown as broken).
  final bool careCount;

  /// Pro: a heads-up notification when a tracked supply runs low.
  final bool refill;

  /// Keeps engagement notifications (summary, refill) out of the night.
  /// Dose reminders the person scheduled are never moved.
  final bool quietHours;

  /// Minutes after local midnight; the window may wrap past midnight.
  final int quietStartMinute;
  final int quietEndMinute;

  /// Minutes after midnight on Sunday for the weekly summary.
  final int weeklyMinute;

  static const followUpDelay = Duration(minutes: 30);
  static const snoozeDelay = Duration(minutes: 15);

  /// True when [minuteOfDay] falls inside the quiet window.
  bool isQuiet(int minuteOfDay) {
    if (!quietHours || quietStartMinute == quietEndMinute) return false;
    if (quietStartMinute < quietEndMinute) {
      return minuteOfDay >= quietStartMinute && minuteOfDay < quietEndMinute;
    }
    return minuteOfDay >= quietStartMinute || minuteOfDay < quietEndMinute;
  }

  ReminderSettings copyWith({
    bool? followUp,
    bool? weeklySummary,
    bool? thanks,
    bool? careCount,
    bool? refill,
    bool? quietHours,
    int? quietStartMinute,
    int? quietEndMinute,
  }) => ReminderSettings(
    followUp: followUp ?? this.followUp,
    weeklySummary: weeklySummary ?? this.weeklySummary,
    thanks: thanks ?? this.thanks,
    careCount: careCount ?? this.careCount,
    refill: refill ?? this.refill,
    quietHours: quietHours ?? this.quietHours,
    quietStartMinute: quietStartMinute ?? this.quietStartMinute,
    quietEndMinute: quietEndMinute ?? this.quietEndMinute,
    weeklyMinute: weeklyMinute,
  );

  Map<String, Object?> toJson() => {
    'followUp': followUp,
    'weeklySummary': weeklySummary,
    'thanks': thanks,
    'careCount': careCount,
    'refill': refill,
    'quietHours': quietHours,
    'quietStart': quietStartMinute,
    'quietEnd': quietEndMinute,
    'weeklyMinute': weeklyMinute,
  };

  /// Tolerates missing or junk fields (older app versions, manual edits).
  factory ReminderSettings.fromJson(Map<String, Object?> json) {
    bool flag(String key) => json[key] is bool ? json[key]! as bool : true;
    int minute(String key, int fallback) {
      final value = json[key];
      return value is int && value >= 0 && value < 24 * 60 ? value : fallback;
    }

    return ReminderSettings(
      followUp: flag('followUp'),
      weeklySummary: flag('weeklySummary'),
      thanks: flag('thanks'),
      careCount: flag('careCount'),
      refill: flag('refill'),
      quietHours: flag('quietHours'),
      quietStartMinute: minute('quietStart', 22 * 60),
      quietEndMinute: minute('quietEnd', 7 * 60),
      weeklyMinute: minute('weeklyMinute', 18 * 60),
    );
  }
}

/// Saves [ReminderSettings] in SharedPreferences. Reads never throw.
abstract final class ReminderSettingsStore {
  static const key = 'reminder_settings_v1';

  /// Bumped on every save. Part of the reminder signature, so a settings
  /// change re-plans pending copy even without an explicit reschedule.
  static final ValueNotifier<int> changes = ValueNotifier(0);

  static Future<ReminderSettings> read() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(key);
      if (raw == null) return const ReminderSettings();
      final json = jsonDecode(raw);
      if (json is! Map) return const ReminderSettings();
      return ReminderSettings.fromJson({
        for (final e in json.entries) '${e.key}': e.value,
      });
    } on Object catch (error, stack) {
      AppLog.error('store.reminder_settings_failed', error, stack, {
        'op': 'read',
      });
      return const ReminderSettings();
    }
  }

  static Future<void> write(ReminderSettings settings) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, jsonEncode(settings.toJson()));
      changes.value++;
    } on Object catch (error, stack) {
      AppLog.error('store.reminder_settings_failed', error, stack, {
        'op': 'write',
      });
    }
  }
}
