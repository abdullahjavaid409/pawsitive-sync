import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:pawsitive_sync/core/logging/app_log.dart';
import 'package:pawsitive_sync/data/dose_reminders.dart';
import 'package:pawsitive_sync/data/household_api.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A device push token ready for `POST /v1/devices/register`.
class PushToken {
  const PushToken({
    required this.platform,
    required this.token,
    required this.environment,
  });

  /// `ios` or `android`.
  final String platform;

  /// `apns:<hex>` or `fcm:<id>`.
  final String token;

  /// `sandbox` (debug builds) or `production` (release builds).
  final String environment;
}

/// One dose named in a household push payload (`doses` array).
class PushDose {
  const PushDose({
    required this.medicationId,
    required this.part,
    required this.day,
    required this.outcome,
    this.logId = '',
  });

  final String medicationId;
  final String part;
  final String day;
  final String outcome;
  final String logId;

  /// Same shape as `Dose.id` / the reminder target: `<medicationId>.<part>`.
  String get doseId => '$medicationId.$part';

  /// Given or skipped closes the dose; "not sure" leaves the reminder up.
  bool get resolves => outcome == 'given' || outcome == 'skipped';
}

/// The native half of push. iOS: `AppDelegate`'s `pawsitive_sync/push`
/// channel. Android has no client yet (needs Firebase; see docs/PUSH_SETUP.md).
abstract class PushPlatform {
  /// The device token if the OS already has one, else null — never waits on
  /// APNs (a simulator, a slow APNs or no network may never answer). A token
  /// that arrives later is delivered through [listen]'s `onToken`.
  Future<PushToken?> token();

  /// Delivers payloads of pushes the app received (foreground, background
  /// wake, or queued natively from before Dart was ready), and tokens that
  /// arrive (or change) after [token] was asked.
  void listen(
    Future<void> Function(Map<String, Object?> payload) onMessage, {
    void Function(PushToken token)? onToken,
  });
}

/// [PushPlatform] over a method channel.
class MethodChannelPushPlatform implements PushPlatform {
  MethodChannelPushPlatform([MethodChannel? channel])
    : _channel = channel ?? const MethodChannel('pawsitive_sync/push');

  final MethodChannel _channel;

  @override
  Future<PushToken?> token() async {
    if (kIsWeb || !Platform.isIOS) {
      // Android push needs google-services.json + Firebase (documented debt).
      AppLog.event('push.platform_unsupported', {
        'platform': kIsWeb ? 'web' : Platform.operatingSystem,
      });
      return null;
    }
    try {
      // Native answers at once with the token it already has (or null) and
      // asks APNs in the background; the real token comes via `token` calls.
      final hex = await _channel
          .invokeMethod<String>('register')
          .timeout(const Duration(seconds: 2));
      return _iosToken(hex);
    } on TimeoutException {
      return null;
    } on PlatformException catch (error) {
      AppLog.event('push.token_failed', {'reason': error.code});
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  static PushToken? _iosToken(Object? hex) {
    if (hex is! String || !RegExp(r'^[0-9a-fA-F]{64,200}$').hasMatch(hex)) {
      return null;
    }
    return PushToken(
      platform: 'ios',
      token: 'apns:${hex.toLowerCase()}',
      // Xcode/App Store export switches aps-environment to production for
      // release builds; debug builds talk to the APNs sandbox.
      environment: kReleaseMode ? 'production' : 'sandbox',
    );
  }

  @override
  void listen(
    Future<void> Function(Map<String, Object?> payload) onMessage, {
    void Function(PushToken token)? onToken,
  }) {
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'message':
          final args = call.arguments;
          if (args is Map) {
            await onMessage({
              for (final e in args.entries) '${e.key}': e.value,
            });
          }
        case 'token':
          final token = _iosToken(call.arguments);
          if (token != null) onToken?.call(token);
        case 'token_error':
          PushService.noteTokenUnavailable('${call.arguments ?? 'apns_error'}');
      }
      return null;
    });
    // Pushes that woke the app before Dart was listening are flushed now.
    unawaited(_channel.invokeMethod<void>('ready').catchError((Object _) {}));
  }
}

/// Registers this device for household push and handles what arrives.
abstract final class PushService {
  static const _tokenKey = 'push_device_token_v1';
  static const _enabledKey = 'push_household_enabled';
  static const _deliveryKey = 'push_remote_delivery_v1';
  static const _registeredKey = 'push_registered_v2';

  /// Swapped in tests.
  @visibleForTesting
  static PushPlatform platform = MethodChannelPushPlatform();

  /// The household link to register with when a token arrives late.
  static HouseholdApi? _api;

  /// Newest token from the OS (late arrivals included).
  static PushToken? _latest;

  static bool _unavailableLogged = false;

  /// Logs `push.token_unavailable` once per run (simulator, notifications
  /// off, APNs slow or unreachable) and carries on — never an error.
  static void noteTokenUnavailable(String reason) {
    if (_unavailableLogged) return;
    _unavailableLogged = true;
    AppLog.event('push.token_unavailable', {'reason': reason});
  }

  /// A token arrived after connect (or APNs issued a new one): register it
  /// in the background, skipped when unchanged.
  static void _onToken(PushToken token) {
    // iOS re-reports the same token every time the app asks for one (and
    // registering asks): an unchanged token must not register again, or
    // ask → token → register → ask… loops forever on a real device.
    final same = _latest?.token == token.token &&
        _latest?.environment == token.environment;
    _latest = token;
    if (same) return;
    final api = _api;
    if (api == null || api.token == null) return;
    AppLog.unawaitedLogged(
      // The token is in hand: don't ask the OS again (that re-triggers it).
      registerIfConnected(api, force: false, known: token),
      'push.register_failed',
    );
  }

  /// The server registration in flight; callers queue behind it so two
  /// can't both pass the "unchanged" check. Asking the OS for its token is
  /// outside the lock, so a slow APNs never holds up a token in hand.
  static Future<void>? _inFlight;

  @visibleForTesting
  static void resetForTest() {
    _api = null;
    _latest = null;
    _inFlight = null;
    _unavailableLogged = false;
  }

  /// Called after a push says someone else logged doses (sync + reschedule).
  /// Set by `main.dart`; null in most tests.
  static Future<void> Function(List<PushDose> doses)? onDosesLoggedElsewhere;

  static Future<bool> householdPushEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_enabledKey) ?? true;
  }

  static Future<void> setHouseholdPushEnabled(bool on) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, on);
    AppLog.event('push.preference', {'enabled': on});
  }

  /// True once the server confirmed it can push to this device; then the
  /// local "partner logged" alert after a sync would be a duplicate.
  static Future<bool> remoteDeliveryActive() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_deliveryKey) ?? false;
  }

  /// Forgets this device's push state and preference (account deletion,
  /// leaving): the next household registers afresh.
  static Future<void> clearLocal() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_enabledKey);
    await prefs.remove(_deliveryKey);
    await prefs.remove(_registeredKey);
  }

  /// Sends the real device token to the household. [force] (a new session)
  /// always sends; otherwise it is skipped when the same token, setting and
  /// household were already registered — one call per change, not per launch.
  /// Never throws; a failure is logged and retried on the next connect/launch.
  static Future<void> registerIfConnected(
    HouseholdApi? api, {
    bool force = true,
    PushToken? known,
  }) async {
    if (api == null) {
      AppLog.event('push.register_skipped', {'reason': 'no_api'});
      return;
    }
    final session = api.token;
    if (session == null || session.isEmpty) {
      AppLog.event('push.register_skipped', {'reason': 'not_connected'});
      return;
    }
    _api = api;
    try {
      final device = known ?? await platform.token() ?? _latest;
      if (device == null) {
        // Not an error: registration happens when the token arrives.
        noteTokenUnavailable('no_token_yet');
        AppLog.event('push.register_skipped', {'reason': 'no_token'});
        return;
      }
      _latest = device;
      final previous = _inFlight;
      final done = Completer<void>();
      _inFlight = done.future;
      try {
        await previous;
        await _send(api, session, device, force: force);
      } finally {
        done.complete();
        if (identical(_inFlight, done.future)) _inFlight = null;
      }
    } catch (error, stack) {
      AppLog.error('push.register_failed', error, stack);
    }
  }

  static Future<void> _send(
    HouseholdApi api,
    String session,
    PushToken device, {
    required bool force,
  }) async {
    try {
      final enabled = await householdPushEnabled();
      final prefs = await SharedPreferences.getInstance();
      // The session's hash only tells households apart; it is not a secret.
      final signature =
          '${session.hashCode}|${device.token}|$enabled|${device.environment}';
      if (!force && prefs.getString(_registeredKey) == signature) {
        AppLog.event('push.register_skipped', {'reason': 'unchanged'});
        return;
      }
      final delivery = await api.registerDevice(
        platform: device.platform,
        token: device.token,
        pushEnabled: enabled,
        environment: device.environment,
      );
      await prefs.setString(_tokenKey, device.token);
      await prefs.setString(_registeredKey, signature);
      await prefs.setBool(_deliveryKey, delivery);
      AppLog.event('push.registered', {
        'platform': device.platform,
        'environment': device.environment,
        'delivery': delivery,
      });
    } on HouseholdException catch (error) {
      // Timeout or offline: not recorded as registered, so it is retried.
      AppLog.event('push.register_failed', {
        'kind': error.kind.name,
        if (error.timedOut) 'timedOut': true,
      });
    } catch (error, stack) {
      AppLog.error('push.register_failed', error, stack);
    }
  }

  /// Starts receiving push payloads from the native side.
  static void listen() =>
      platform.listen(handleRemoteMessage, onToken: _onToken);

  /// Parses the `doses` of a `dose_logged` payload. Tolerates junk.
  static List<PushDose> dosesFrom(Map<String, Object?> payload) {
    if (payload['type'] != 'dose_logged') return const [];
    final raw = payload['doses'];
    if (raw is! List) return const [];
    return [
      for (final item in raw)
        if (item is Map &&
            item['medicationId'] is String &&
            item['part'] is String &&
            item['day'] is String)
          PushDose(
            medicationId: item['medicationId'] as String,
            part: item['part'] as String,
            day: item['day'] as String,
            outcome: '${item['outcome'] ?? 'given'}',
            logId: '${item['logId'] ?? ''}',
          ),
    ];
  }

  /// A household push arrived: cancel this phone's reminder if it was for a
  /// dose someone else just gave or skipped, then let the app refresh.
  /// Safe to receive twice (alert + silent push): both steps are idempotent.
  static Future<void> handleRemoteMessage(Map<String, Object?> payload) async {
    final doses = dosesFrom(payload);
    if (doses.isEmpty) {
      AppLog.event('push.received', {'type': '${payload['type'] ?? ''}'});
      return;
    }
    AppLog.event('push.received', {
      'type': 'dose_logged',
      'doses': doses.length,
    });
    final resolved = [
      for (final dose in doses)
        if (dose.resolves) dose,
    ];
    if (resolved.isNotEmpty) await DoseReminders.cancelForDoses(resolved);
    final refresh = onDosesLoggedElsewhere;
    if (refresh == null) return;
    try {
      await refresh(doses);
    } catch (error, stack) {
      AppLog.error('push.refresh_failed', error, stack);
    }
  }

  /// Shows a local alert when a household partner logs a dose (after sync).
  /// Skipped once the server pushes to this device (it would be a duplicate).
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
    if (await remoteDeliveryActive()) {
      AppLog.event('push.partner_skipped', {'reason': 'remote_push'});
      return;
    }
    try {
      // Through DoseReminders: one plugin owner, so taps keep working.
      await DoseReminders.showHousehold(
        logId,
        'Dose logged',
        '$who gave $medicationName to $petName',
      );
      AppLog.event('push.partner_logged', {'logId': logId});
    } catch (error, stack) {
      AppLog.error('push.partner_logged_failed', error, stack, {
        'logId': logId,
      });
    }
  }
}
