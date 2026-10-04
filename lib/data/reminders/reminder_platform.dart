import 'dart:async';
import 'dart:io';
import 'dart:ui' show DartPluginRegistrant;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pawsitive_sync/core/config/app_config.dart';
import 'package:pawsitive_sync/core/logging/app_log.dart';
import 'package:pawsitive_sync/data/reminders/reminder_plan.dart';
import 'package:pawsitive_sync/data/reminders/reminder_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;

/// Whether the OS lets the app show notifications.
enum ReminderPermission { granted, denied, unknown }

/// Notification action ids (iOS category actions / Android actions).
abstract final class ReminderActions {
  static const given = 'given';
  static const snooze = 'snooze';

  /// Grouped notifications: opens Today (several doses, so no "Given").
  static const open = 'open';
  static const doseCategory = 'dose_due';

  /// iOS category for a grouped notification (Open + Snooze 15 min).
  static const groupCategory = 'doses_due';

  /// Android notification group for every dose reminder.
  static const androidGroup = 'com.pawsitivesync.app.doses';
}

/// A pending notification as the OS reports it.
class PendingReminder {
  const PendingReminder(this.id, this.payload);
  final int id;
  final String? payload;
}

/// A tap or an action on one of our notifications.
class ReminderResponse {
  const ReminderResponse({this.actionId, this.payload});

  /// Null (or empty) for a plain tap.
  final String? actionId;
  final String? payload;
}

/// The OS half of reminders. [PluginReminderPlatform] in the app; tests
/// use a fake so scheduling decisions can be asserted without a device.
abstract class ReminderPlatform {
  Future<void> initialize(void Function(ReminderResponse) onResponse);
  Future<ReminderPermission> permission();

  /// Shows the system prompt (once per install on iOS). True when allowed.
  Future<bool> requestPermission();

  /// Android 12+: exact alarms allowed. Always true elsewhere.
  Future<bool> canScheduleExact();

  /// Android 14+: opens the system page for exact alarms.
  Future<bool> requestExact();

  Future<List<PendingReminder>> pending();
  Future<void> schedule(PlannedNotification notification, {required bool exact});
  Future<void> show(
    int id,
    String title,
    String body, {
    required ReminderKind kind,
    String? payload,
  });
  Future<void> cancel(int id);
  Future<void> cancelAll();

  /// The tap/action that cold-started the app, if any.
  Future<ReminderResponse?> launchResponse();

  /// IANA zone of the device, e.g. `Europe/London`.
  Future<String> timezoneName();
}

/// Snoozes one dose for [ReminderSettings.snoozeDelay]. Shared by the
/// background action isolate, the in-app lock screen and the main isolate,
/// so it only uses the payload — never the repository.
abstract final class ReminderSnooze {
  /// `doseId|day` keys snoozed recently; read by the planner (no follow-up
  /// on top of a snooze). SharedPreferences is shared across isolates.
  static const prefsKey = 'reminders_snoozed_v1';

  static Future<bool> apply(
    ReminderPlatform platform,
    ReminderPayload source, {
    DateTime? now,
    Duration delay = ReminderSettings.snoozeDelay,
  }) async {
    if (source.day.isEmpty || (source.doseId.isEmpty && !source.isGroup)) {
      return false;
    }
    final at = tz.TZDateTime.from(
      (now ?? DateTime.now()).add(delay),
      tz.UTC,
    );
    // A group snoozes as one ("Snooze 15 min" for all of its doses).
    final snooze = source.isGroup
        ? ReminderGroups.build(
            kind: ReminderKind.snooze,
            doses: source.group,
            when: at,
            day: source.day,
            groupKey: source.groupKey,
            timeLabel: source.timeLabel,
            shared: source.shared,
          )!
        : PlannedNotification(
            id: ReminderIds.forDose(
              ReminderKind.snooze,
              source.doseId,
              source.day,
            ),
            kind: ReminderKind.snooze,
            when: at,
            title: source.title,
            body: ReminderCopy.snoozeBody(''),
            doseId: source.doseId,
            day: source.day,
          );
    // The follow-up would be a second nudge on top of the one asked for.
    if (source.groupKey.isNotEmpty) {
      await platform.cancel(ReminderIds.of(ReminderKind.followUp, source.groupKey));
    }
    for (final key in source.doseKeys) {
      final split = key.lastIndexOf('|');
      await platform.cancel(
        ReminderIds.forDose(
          ReminderKind.followUp,
          key.substring(0, split),
          source.day,
        ),
      );
    }
    var exact = false;
    try {
      exact = await platform.canScheduleExact();
    } on Object {
      exact = false;
    }
    await platform.schedule(snooze, exact: exact);
    for (final key in source.doseKeys) {
      await remember(key, source.day);
    }
    AppLog.event('reminders.snoozed', {
      'doseId': source.isGroup ? source.group.first.doseId : source.doseId,
      if (source.isGroup) 'doses': source.group.length,
      'minutes': delay.inMinutes,
      'from': source.kind.name,
    });
    return true;
  }

  /// Keeps keys for today and yesterday only.
  static Future<void> remember(String key, String day) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      final keep = [
        for (final k in prefs.getStringList(prefsKey) ?? const <String>[])
          if (k != key && _recent(k, day)) k,
        key,
      ];
      await prefs.setStringList(prefsKey, keep);
    } on Object catch (error, stack) {
      AppLog.error('reminders.snooze_save_failed', error, stack);
    }
  }

  static bool _recent(String key, String today) {
    final split = key.lastIndexOf('|');
    if (split < 0) return false;
    final day = DateTime.tryParse(key.substring(split + 1));
    final ref = DateTime.tryParse(today);
    if (day == null || ref == null) return false;
    return ref.difference(day).inDays <= 1;
  }

  /// Fresh from disk: another isolate may have written since launch.
  static Future<Set<String>> read() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      return {...?prefs.getStringList(prefsKey)};
    } on Object {
      return const {};
    }
  }
}

/// Runs in a background isolate when "Snooze 15 min" is tapped while the
/// app is suspended or killed (no UI is opened for snooze).
@pragma('vm:entry-point')
Future<void> reminderBackgroundResponse(NotificationResponse response) async {
  // Plugins (SharedPreferences) in this isolate need registering.
  DartPluginRegistrant.ensureInitialized();
  if (response.actionId != ReminderActions.snooze) return;
  final payload = ReminderPayload.decode(response.payload);
  if (payload == null) return;
  try {
    final platform = PluginReminderPlatform();
    await platform.initialize((_) {});
    await ReminderSnooze.apply(platform, payload);
  } on Object catch (error, stack) {
    AppLog.error('reminders.snooze_failed', error, stack, {'from': 'background'});
  }
}

/// [ReminderPlatform] over flutter_local_notifications + flutter_timezone.
class PluginReminderPlatform implements ReminderPlatform {
  PluginReminderPlatform([FlutterLocalNotificationsPlugin? plugin])
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;

  AndroidFlutterLocalNotificationsPlugin? get _android => _plugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();

  IOSFlutterLocalNotificationsPlugin? get _ios => _plugin
      .resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin
      >();

  static ReminderResponse _map(NotificationResponse r) =>
      ReminderResponse(actionId: r.actionId, payload: r.payload);

  @override
  Future<void> initialize(void Function(ReminderResponse) onResponse) async {
    final ios = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
      notificationCategories: [
        DarwinNotificationCategory(
          ReminderActions.groupCategory,
          actions: [
            DarwinNotificationAction.plain(
              ReminderActions.open,
              'Open',
              options: {DarwinNotificationActionOption.foreground},
            ),
            DarwinNotificationAction.plain(
              ReminderActions.snooze,
              'Snooze 15 min',
            ),
          ],
        ),
        DarwinNotificationCategory(
          ReminderActions.doseCategory,
          actions: [
            // Opens the app: logging needs the repository and the
            // double-dose check, which only the main isolate has.
            DarwinNotificationAction.plain(
              ReminderActions.given,
              'Given',
              options: {DarwinNotificationActionOption.foreground},
            ),
            DarwinNotificationAction.plain(
              ReminderActions.snooze,
              'Snooze 15 min',
            ),
          ],
        ),
      ],
    );
    await _plugin.initialize(
      InitializationSettings(
        android: const AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: ios,
      ),
      onDidReceiveNotificationResponse: (r) => onResponse(_map(r)),
      onDidReceiveBackgroundNotificationResponse: reminderBackgroundResponse,
    );
  }

  @override
  Future<ReminderPermission> permission() async {
    final android = _android;
    if (android != null) {
      final on = await android.areNotificationsEnabled();
      return on == null
          ? ReminderPermission.unknown
          : on
          ? ReminderPermission.granted
          : ReminderPermission.denied;
    }
    final ios = _ios;
    if (ios != null) {
      final options = await ios.checkPermissions();
      if (options == null) return ReminderPermission.unknown;
      return options.isEnabled
          ? ReminderPermission.granted
          : ReminderPermission.denied;
    }
    return ReminderPermission.unknown;
  }

  @override
  Future<bool> requestPermission() async {
    final android = _android;
    if (android != null) {
      return await android.requestNotificationsPermission() ?? false;
    }
    final ios = _ios;
    if (ios != null) {
      return await ios.requestPermissions(alert: true, sound: true) ?? false;
    }
    return false;
  }

  @override
  Future<bool> canScheduleExact() async {
    final android = _android;
    if (android == null) return true;
    return await android.canScheduleExactNotifications() ?? false;
  }

  @override
  Future<bool> requestExact() async {
    final android = _android;
    if (android == null) return true;
    return await android.requestExactAlarmsPermission() ?? false;
  }

  @override
  Future<List<PendingReminder>> pending() async => [
    for (final r in await _plugin.pendingNotificationRequests())
      PendingReminder(r.id, r.payload),
  ];

  @override
  Future<void> schedule(
    PlannedNotification n, {
    required bool exact,
  }) async {
    final details = await _details(
      n.kind,
      id: n.id,
      photoPath: n.photoPath,
      group: n.isGroup,
      body: n.body,
    );
    Future<void> run(AndroidScheduleMode mode) => _plugin.zonedSchedule(
      n.id,
      n.title,
      n.body,
      n.when,
      details,
      androidScheduleMode: mode,
      payload: n.payload,
    );
    if (!exact) return run(AndroidScheduleMode.inexactAllowWhileIdle);
    try {
      await run(AndroidScheduleMode.exactAllowWhileIdle);
    } on PlatformException catch (error) {
      // Permission revoked between the check and the call: still remind,
      // just possibly a few minutes late.
      AppLog.event('reminders.exact_fallback', {'code': error.code});
      await run(AndroidScheduleMode.inexactAllowWhileIdle);
    }
  }

  @override
  Future<void> show(
    int id,
    String title,
    String body, {
    required ReminderKind kind,
    String? payload,
  }) async {
    await _plugin.show(id, title, body, await _details(kind, id: id), payload: payload);
  }

  @override
  Future<void> cancel(int id) => _plugin.cancel(id);

  @override
  Future<void> cancelAll() => _plugin.cancelAll();

  @override
  Future<ReminderResponse?> launchResponse() async {
    final details = await _plugin.getNotificationAppLaunchDetails();
    final response = details?.notificationResponse;
    if (details?.didNotificationLaunchApp != true || response == null) {
      return null;
    }
    return _map(response);
  }

  @override
  Future<String> timezoneName() async =>
      (await FlutterTimezone.getLocalTimezone().timeout(
        const Duration(seconds: 2),
      )).identifier;

  Future<NotificationDetails> _details(
    ReminderKind kind, {
    required int id,
    String? photoPath,
    bool group = false,
    String body = '',
  }) async {
    switch (kind) {
      case ReminderKind.dose:
      case ReminderKind.followUp:
      case ReminderKind.snooze:
        final photo = photoPath != null && File(photoPath).existsSync()
            ? photoPath
            : null;
        return NotificationDetails(
          android: AndroidNotificationDetails(
            'doses',
            'Medicine reminders',
            channelDescription: 'A reminder when a dose is due.',
            importance: Importance.high,
            priority: Priority.high,
            category: AndroidNotificationCategory.reminder,
            largeIcon: photo == null ? null : FilePathAndroidBitmap(photo),
            // Same-minute doses are already one notification; the group
            // key bundles reminders at different minutes in the shade.
            groupKey: ReminderActions.androidGroup,
            // Long group bodies ("Miso: Insulin · Biscuit: …") wrap.
            styleInformation: group ? BigTextStyleInformation(body) : null,
            actions: <AndroidNotificationAction>[
              if (group)
                const AndroidNotificationAction(
                  ReminderActions.open,
                  'Open',
                  showsUserInterface: true,
                )
              else
                const AndroidNotificationAction(
                  ReminderActions.given,
                  'Given',
                  showsUserInterface: true,
                ),
              const AndroidNotificationAction(
                ReminderActions.snooze,
                'Snooze 15 min',
              ),
            ],
          ),
          iOS: DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: false,
            presentSound: true,
            categoryIdentifier: group
                ? ReminderActions.groupCategory
                : ReminderActions.doseCategory,
            threadIdentifier: 'doses',
            interruptionLevel: AppConfig.iosTimeSensitive
                ? InterruptionLevel.timeSensitive
                : InterruptionLevel.active,
            attachments: await _iosAttachment(photo, id),
          ),
        );
      case ReminderKind.weekly:
      case ReminderKind.refill:
        return const NotificationDetails(
          android: AndroidNotificationDetails(
            'care_updates',
            'Care updates',
            channelDescription: 'Weekly summary and refill heads-ups.',
            importance: Importance.defaultImportance,
            priority: Priority.defaultPriority,
          ),
          iOS: DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: false,
            presentSound: false,
            threadIdentifier: 'care',
            interruptionLevel: InterruptionLevel.passive,
          ),
        );
      case ReminderKind.upkeep:
        // Quiet: no sound, no banner urgency. It only asks for an app open.
        return const NotificationDetails(
          android: AndroidNotificationDetails(
            'reminder_upkeep',
            'Reminder check-ins',
            channelDescription:
                'A quiet note when reminders need the app opened to continue.',
            importance: Importance.low,
            priority: Priority.low,
          ),
          iOS: DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: false,
            presentSound: false,
            threadIdentifier: 'care',
            interruptionLevel: InterruptionLevel.passive,
          ),
        );
      case ReminderKind.alreadyLogged:
      case ReminderKind.household:
        return const NotificationDetails(
          android: AndroidNotificationDetails(
            'household',
            'Household updates',
            channelDescription: 'When a partner or sitter logs a dose.',
            importance: Importance.high,
            priority: Priority.high,
          ),
          iOS: DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: false,
            presentSound: true,
            threadIdentifier: 'household',
          ),
        );
    }
  }

  /// iOS moves an attachment file into its own store, so hand it a copy —
  /// never the pet photo itself. Any failure just means no picture.
  Future<List<DarwinNotificationAttachment>?> _iosAttachment(
    String? photo,
    int id,
  ) async {
    if (photo == null || kIsWeb || !Platform.isIOS) return null;
    try {
      final dir = Directory(
        p.join((await getTemporaryDirectory()).path, 'reminder_photos'),
      );
      await dir.create(recursive: true);
      final copy = await File(photo).copy(p.join(dir.path, '$id.jpg'));
      return [DarwinNotificationAttachment(copy.path)];
    } on Object catch (error) {
      AppLog.event('reminders.photo_skipped', {'reason': '${error.runtimeType}'});
      return null;
    }
  }
}
