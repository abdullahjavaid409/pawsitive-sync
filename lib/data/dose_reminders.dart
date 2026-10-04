import 'dart:convert';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:pawsitive_sync/core/logging/app_log.dart';
import 'package:pawsitive_sync/data/push_service.dart' show PushDose;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pawsitive_sync/data/care_repository.dart';
import 'package:pawsitive_sync/domain/models.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// Local dose reminders. Permission is requested only from the reminder step.
class DoseReminders {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static Future<void>? _ready;

  /// The one scheduled reminder's notification id.
  static const reminderId = 1;

  /// Which dose (and day) the scheduled reminder is for, saved so a push can
  /// cancel it even when the app was killed and relaunched in the background.
  static const _targetKey = 'reminder_target_v1';

  /// Cancels a notification by id. Swapped in tests (no plugin there).
  @visibleForTesting
  static Future<void> Function(int id) cancelNotification = (id) async {
    await prepare();
    await _plugin.cancel(id);
  };

  static Future<void> _saveTarget(String doseId, DateTime localWhen) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _targetKey,
        jsonEncode({'doseId': doseId, 'day': _dayKey(localWhen)}),
      );
    } on Object catch (error, stack) {
      AppLog.error('reminders.target_save_failed', error, stack);
    }
  }

  static Future<void> _clearTarget() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_targetKey);
    } on Object {
      // Worst case a later push cancels nothing.
    }
  }

  /// Cancels the scheduled reminder when it is for one of [doses] (someone
  /// else gave or skipped it). Returns true when it cancelled. Idempotent.
  static Future<bool> cancelForDoses(List<PushDose> doses) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_targetKey);
      if (raw == null) return false;
      final target = jsonDecode(raw);
      if (target is! Map) return false;
      final match = doses.any(
        (dose) => dose.doseId == target['doseId'] && dose.day == target['day'],
      );
      if (!match) {
        AppLog.event('reminders.push_no_match', {'doses': doses.length});
        return false;
      }
      await cancelNotification(reminderId);
      await prefs.remove(_targetKey);
      AppLog.event('reminders.cancelled_by_push', {
        'doseId': '${target['doseId']}',
      });
      return true;
    } on Object catch (error, stack) {
      AppLog.error('reminders.push_cancel_failed', error, stack);
      return false;
    }
  }

  /// Loads time zones and the notification plugin once. Concurrent callers
  /// share the same setup; a failure is logged and retried on the next call.
  static Future<void> prepare() => _ready ??= _prepare();

  static Future<void> _prepare() async {
    try {
      tzdata.initializeTimeZones();
      const android = AndroidInitializationSettings('@mipmap/ic_launcher');
      const ios = DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      );
      await _plugin.initialize(
        const InitializationSettings(android: android, iOS: ios),
      );
      AppLog.event('reminders.ready');
    } catch (error, stack) {
      _ready = null;
      AppLog.error('reminders.prepare_failed', error, stack);
      rethrow;
    }
  }

  /// Shows the system permission dialog. Returns false when the person says no.
  static Future<bool> ask() async {
    try {
      return await _ask();
    } catch (error, stack) {
      AppLog.error('reminders.permission_failed', error, stack);
      return false;
    }
  }

  static Future<bool> _ask() async {
    await prepare();
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (android != null) {
      final granted = await android.requestNotificationsPermission();
      AppLog.event('reminders.permission', {'allowed': granted ?? false});
      return granted ?? false;
    }
    final ios = _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >();
    if (ios != null) {
      final granted = await ios.requestPermissions(
        alert: true,
        badge: false,
        sound: true,
      );
      AppLog.event('reminders.permission', {'allowed': granted ?? false});
      return granted ?? false;
    }
    AppLog.event('reminders.permission', {
      'allowed': false,
      'reason': 'unsupported_platform',
    });
    return false;
  }

  static Future<void> cancel() async {
    try {
      await prepare();
      await _plugin.cancelAll();
      await _clearTarget();
      AppLog.event('reminders.cancelled');
    } catch (error, stack) {
      AppLog.error('reminders.cancel_failed', error, stack);
    }
  }

  /// Schedules the next due dose only. Nothing is scheduled when permission was refused.
  static Future<void> scheduleNext(CareRepository care) async {
    try {
      await prepare();
      await _plugin.cancelAll();
      await _clearTarget();
    } catch (error, stack) {
      AppLog.error('reminders.schedule_failed', error, stack);
      return;
    }
    final dose = care.nextDue;
    if (dose == null) {
      AppLog.event('reminders.none_due');
      return;
    }
    Pet? pet;
    for (final item in care.pets) {
      if (item.id == dose.petId) pet = item;
    }
    final when = _next(dose);
    final petName = pet?.name ?? 'Your pet';
    final amount = dose.amount.isEmpty
        ? dose.name
        : '${dose.name}, ${dose.amount}';
    try {
      await _plugin.zonedSchedule(
        reminderId,
        'Time for $petName',
        '$amount is due. Open the app and tap I gave this.',
        when,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'doses',
            'Medicine reminders',
            channelDescription: 'A reminder when a dose is due.',
            importance: Importance.high,
            priority: Priority.high,
          ),
          iOS: DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: false,
            presentSound: true,
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
      await _saveTarget(dose.id, when.toLocal());
      AppLog.event('reminders.scheduled', {'doseId': dose.id});
    } catch (error, stack) {
      AppLog.error('reminders.schedule_failed', error, stack, {
        'doseId': dose.id,
      });
    }
  }

  /// Reminds again after snoozing from the lock screen.
  static Future<bool> snoozeMinutes(
    CareRepository care,
    int minutes, {
    Dose? target,
  }) async {
    try {
      await prepare();
      final dose = target ?? care.nextDue;
      if (dose == null || dose.status != DoseStatus.due) {
        AppLog.event('lock.snooze_skipped', {'reason': 'nothing_due'});
        return false;
      }
      Pet? pet;
      for (final item in care.pets) {
        if (item.id == dose.petId) pet = item;
      }
      final when = tz.TZDateTime.now(tz.local).add(Duration(minutes: minutes));
      final petName = pet?.name ?? 'Your pet';
      final amount = dose.amount.isEmpty
          ? dose.name
          : '${dose.name}, ${dose.amount}';
      await _plugin.zonedSchedule(
        reminderId,
        'Time for $petName',
        '$amount is due. Open the app and tap I gave this.',
        when,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'doses',
            'Medicine reminders',
            channelDescription: 'A reminder when a dose is due.',
            importance: Importance.high,
            priority: Priority.high,
          ),
          iOS: DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: false,
            presentSound: true,
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
      await _saveTarget(dose.id, DateTime.now());
      AppLog.event('lock.snoozed', {'minutes': minutes, 'doseId': dose.id});
      return true;
    } catch (error, stack) {
      AppLog.error('lock.snooze_failed', error, stack);
      return false;
    }
  }
}

String _dayKey(DateTime t) =>
    '${t.year.toString().padLeft(4, '0')}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';

tz.TZDateTime _next(Dose dose) {
  final match = RegExp(r'(\d{1,2}):(\d{2}) ([AP]M)').firstMatch(dose.subtitle);
  var hour = switch (dose.part) {
    DayPart.morning => 8,
    DayPart.afternoon => 13,
    DayPart.evening => 20,
  };
  var minute = 0;
  if (match != null) {
    hour = int.parse(match.group(1)!);
    minute = int.parse(match.group(2)!);
    final pm = match.group(3) == 'PM';
    if (pm && hour < 12) hour += 12;
    if (!pm && hour == 12) hour = 0;
  }
  final now = DateTime.now();
  var local = DateTime(now.year, now.month, now.day, hour, minute);
  if (!local.isAfter(now)) local = local.add(const Duration(days: 1));
  return tz.TZDateTime.now(tz.UTC).add(local.difference(now));
}
