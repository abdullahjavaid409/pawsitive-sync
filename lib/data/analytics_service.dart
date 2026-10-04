import 'package:dio/dio.dart';
import 'package:pawsitive_sync/core/config/app_config.dart';
import 'package:pawsitive_sync/core/logging/app_log.dart';

/// Privacy-light funnel analytics — aggregate counts on server, no PII.
abstract final class AnalyticsService {
  static const _enabled = AppConfig.analyticsEnabled;

  static final _buffer = <String>[];
  static const _maxBuffered = 200;
  static final _dio = Dio(
    BaseOptions(
      baseUrl: AppConfig.apiBaseUrl.replaceFirst(RegExp(r'/$'), ''),
      connectTimeout: const Duration(seconds: 5),
      receiveTimeout: const Duration(seconds: 5),
    ),
  );

  static const _funnelEvents = {
    'onboarding.finished',
    'dose.log.completed',
    'household.connected',
    'household.joined',
    'billing.purchase.completed',
    'billing.pro.unlocked',
    'care_event.added',
  };

  static void track(String name) {
    if (!_enabled || !AppConfig.hasApi || !_funnelEvents.contains(name)) return;
    _buffer.add(name);
    if (_buffer.length >= 8) {
      AppLog.unawaitedLogged(flush(), 'analytics.flush_failed');
    }
  }

  static Future<void> flush() async {
    if (!_enabled || !AppConfig.hasApi || _buffer.isEmpty) return;
    final events = List<String>.from(_buffer);
    _buffer.clear();
    try {
      await _dio.post<void>(
        '/v1/analytics/batch',
        data: {
          'events': [
            for (final name in events) {'name': name},
          ],
        },
      );
      AppLog.event('analytics.flushed', {'count': events.length});
    } catch (error, stack) {
      // Keep the counts for the next flush, capped so a long offline stretch
      // can't grow the buffer without bound.
      _buffer.insertAll(0, events);
      if (_buffer.length > _maxBuffered) {
        _buffer.removeRange(0, _buffer.length - _maxBuffered);
      }
      AppLog.error('analytics.flush_failed', error, stack, {
        'count': events.length,
      });
    }
  }
}
