import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:pawsitive_sync/core/logging/app_log.dart';
import 'package:pawsitive_sync/data/household_api.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Registers this device for household activity push (FCM when configured).
abstract final class PushService {
  static const _tokenKey = 'push_device_token_v1';
  static const _enabledKey = 'push_household_enabled';

  static Future<bool> householdPushEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_enabledKey) ?? true;
  }

  static Future<void> setHouseholdPushEnabled(bool on) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, on);
    AppLog.event('push.preference', {'enabled': on});
  }

  static Future<String> _deviceToken() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_tokenKey);
    if (saved != null && saved.isNotEmpty) return saved;
    final token = 'local:${DateTime.now().microsecondsSinceEpoch}';
    await prefs.setString(_tokenKey, token);
    return token;
  }

  static String get _platform {
    if (kIsWeb) return 'other';
    if (Platform.isIOS) return 'ios';
    if (Platform.isAndroid) return 'android';
    return 'other';
  }

  static Future<void> registerIfConnected(HouseholdApi? api) async {
    if (api == null) {
      AppLog.event('push.register_skipped', {'reason': 'no_api'});
      return;
    }
    if (api.token == null || api.token!.isEmpty) {
      AppLog.event('push.register_skipped', {'reason': 'not_connected'});
      return;
    }
    try {
      final token = await _deviceToken();
      final enabled = await householdPushEnabled();
      await api.registerDevice(
        platform: _platform,
        token: token,
        pushEnabled: enabled,
      );
      AppLog.event('push.registered', {'platform': _platform});
    } catch (_) {
      AppLog.event('push.register_failed');
    }
  }

  static final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();
  static var _localReady = false;

  static Future<void> _ensureLocal() async {
    if (_localReady) return;
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    await _local.initialize(
      const InitializationSettings(android: android, iOS: ios),
    );
    _localReady = true;
  }

  /// Shows a local alert when a household partner logs a dose (after sync).
  static Future<void> notifyPartnerLogged({
    required String logId,
    required String who,
    required String medicationName,
    required String petName,
  }) async {
    if (logId.isEmpty) {
      AppLog.event('push.partner_skipped', {'reason': 'empty_log_id'});
      return;
    }
    if (!await householdPushEnabled()) {
      AppLog.event('push.partner_skipped', {'reason': 'disabled'});
      return;
    }
    try {
      await _ensureLocal();
      final id = logId.hashCode & 0x7fffffff;
      await _local.show(
        id,
        'Dose logged',
        '$who gave $medicationName to $petName',
        const NotificationDetails(
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
          ),
        ),
      );
      AppLog.event('push.partner_logged', {'logId': logId});
    } catch (_) {
      AppLog.event('push.partner_logged_failed', {'logId': logId});
    }
  }
}
