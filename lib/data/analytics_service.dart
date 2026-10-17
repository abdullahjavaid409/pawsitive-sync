import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:pawsitive_sync/core/config/app_config.dart';
import 'package:pawsitive_sync/core/logging/app_log.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Privacy-light funnel analytics: counts per event name, no user id, no
/// PII. The phone keeps the counts and sends them at most once a day in one
/// small request; the server adds them into one row per event per day.
///
/// Cost: one request per active phone per day, a few hundred bytes. Free
/// phones that never connect to a household still send these counts, which
/// is how we see where the funnel loses people.
abstract final class AnalyticsService {
  static const _enabled = AppConfig.analyticsEnabled;

  static const _countsKey = 'analytics.counts.v2';
  static const _lastSentKey = 'analytics.last_sent_day';

  /// Distinct names kept between sends, so a long offline stretch can't
  /// grow without bound.
  static const _maxNames = 60;

  static final _counts = <String, int>{};
  static bool _loaded = false;

  static final _dio = Dio(
    BaseOptions(
      baseUrl: AppConfig.apiBaseUrl.replaceFirst(RegExp(r'/$'), ''),
      connectTimeout: const Duration(seconds: 5),
      receiveTimeout: const Duration(seconds: 5),
    ),
  );

  /// Counted as is.
  static const _funnelEvents = {
    'onboarding.finished',
    'dose.log.completed',
    'household.connected',
    'household.joined',
    'billing.purchase.completed',
    'billing.pro.unlocked',
    'billing.trial.tap',
    'billing.rc.purchase_success',
    'billing.restore.completed',
    'invite.share_tapped',
    'care_event.added',
  };

  /// Counted per value of one field, so the funnel shows *where*:
  /// `billing.paywall.opened.invite`, `onboarding.step.pet_basics`.
  static const _splitBy = {
    'billing.paywall.opened': 'placement',
    'onboarding.step': 'step',
  };

  static final _safeValue = RegExp(r'^[a-z0-9_]{1,32}$');

  /// The name this event is counted under, or null when it isn't counted.
  @visibleForTesting
  static String? keyFor(String name, Map<String, Object?> fields) {
    if (_funnelEvents.contains(name)) return name;
    final field = _splitBy[name];
    if (field == null) return null;
    final value = '${fields[field] ?? 'unknown'}'.toLowerCase();
    return _safeValue.hasMatch(value) ? '$name.$value' : '$name.other';
  }

  static void track(String name, [Map<String, Object?> fields = const {}]) {
    if (!_enabled || !AppConfig.hasApi) return;
    final key = keyFor(name, fields);
    if (key == null) return;
    if (!_counts.containsKey(key) && _counts.length >= _maxNames) return;
    _counts[key] = (_counts[key] ?? 0) + 1;
  }

  @visibleForTesting
  static int get bufferedCount =>
      _counts.values.fold(0, (sum, count) => sum + count);

  /// Seeds the counts in tests (tracking is off without a compiled-in API).
  @visibleForTesting
  static void debugAdd(String name) => _counts[name] = (_counts[name] ?? 0) + 1;

  /// Drops unsent counts (account deletion).
  static Future<void> clear() async {
    _counts.clear();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_countsKey);
    } on Object catch (error, stack) {
      AppLog.error('analytics.clear_failed', error, stack);
    }
  }

  /// Called when the app goes to the background: saves the counts on the
  /// phone, then sends them if nothing was sent today.
  static Future<void> flush({DateTime? now}) async {
    if (!_enabled || !AppConfig.hasApi) return;
    final prefs = await SharedPreferences.getInstance();
    await _mergeSaved(prefs);
    if (_counts.isEmpty) return;
    await prefs.setString(_countsKey, jsonEncode(_counts));
    final today = _day(now ?? DateTime.now());
    if (prefs.getString(_lastSentKey) == today) return;

    final sending = Map<String, int>.from(_counts);
    try {
      await _dio.post<void>(
        '/v1/analytics/batch',
        data: {
          'events': [
            for (final MapEntry(:key, :value) in sending.entries)
              {'name': key, 'count': value},
          ],
        },
      );
      // Only what was sent is removed; counts added meanwhile stay.
      for (final MapEntry(:key, :value) in sending.entries) {
        final left = (_counts[key] ?? 0) - value;
        if (left > 0) {
          _counts[key] = left;
        } else {
          _counts.remove(key);
        }
      }
      await prefs.setString(_countsKey, jsonEncode(_counts));
      await prefs.setString(_lastSentKey, today);
      AppLog.event('analytics.flushed', {
        'names': sending.length,
        'count': sending.values.fold<int>(0, (a, b) => a + b),
      });
    } catch (error, stack) {
      // Kept on the phone for tomorrow's send.
      AppLog.error('analytics.flush_failed', error, stack, {
        'names': sending.length,
      });
    }
  }

  static Future<void> _mergeSaved(SharedPreferences prefs) async {
    if (_loaded) return;
    _loaded = true;
    final raw = prefs.getString(_countsKey);
    if (raw == null) return;
    try {
      final saved = (jsonDecode(raw) as Map).cast<String, Object?>();
      for (final MapEntry(:key, :value) in saved.entries) {
        if (value is int && value > 0) {
          _counts[key] = (_counts[key] ?? 0) + value;
        }
      }
    } on Object catch (error, stack) {
      AppLog.error('analytics.saved_unreadable', error, stack);
    }
  }

  static String _day(DateTime time) =>
      '${time.year}-${time.month.toString().padLeft(2, '0')}-'
      '${time.day.toString().padLeft(2, '0')}';
}
