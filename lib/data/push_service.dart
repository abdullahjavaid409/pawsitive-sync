import 'dart:io';

import 'package:flutter/foundation.dart';
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
    if (api == null || api.token == null) return;
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
}
