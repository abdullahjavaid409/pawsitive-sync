import 'package:flutter/foundation.dart' show kReleaseMode;

/// One place for app settings. Defaults are the live API and RevenueCat.
abstract final class AppConfig {
  static const _productionApi =
      'https://pawsitive-api-production.up.railway.app';

  /// Household sync server. Every build (debug, profile, release) uses the
  /// live Railway API. Override with `--dart-define=API_BASE_URL=…` (the
  /// integration tests point at a local backend); an empty value = offline.
  static const apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: _productionApi,
  );

  /// Numeric App Store ID (App Store Connect → App Information → Apple ID).
  /// Empty until set: invites share the code only, never a dead link.
  static const appStoreId = String.fromEnvironment('APP_STORE_ID');

  /// RevenueCat iOS public SDK key — public by design, so it ships as the
  /// default and every build talks to RevenueCat. Pro comes only from here.
  static const revenueCatIosKey = String.fromEnvironment(
    'REVENUECAT_IOS_KEY',
    defaultValue: 'appl_cFhDWMzoxMhLmHBKcwwODdKVyac',
  );

  /// RevenueCat Android public key. Empty = Free on Android.
  static const revenueCatAndroidKey = String.fromEnvironment(
    'REVENUECAT_ANDROID_KEY',
  );

  /// Anonymous usage counts (no names, no pets). Off when API is empty.
  static const analyticsEnabled = bool.fromEnvironment(
    'ANALYTICS_ENABLED',
    defaultValue: kReleaseMode,
  );

  /// iOS Time Sensitive interruption level for dose reminders. Only turn
  /// on once the `com.apple.developer.usernotifications.time-sensitive`
  /// entitlement is in Runner.entitlements and the provisioning profile —
  /// without it iOS treats the level as "active" anyway, so off is safe.
  static const iosTimeSensitive = bool.fromEnvironment('IOS_TIME_SENSITIVE');

  static bool get hasApi => apiBaseUrl.trim().isNotEmpty;

  static bool get hasRevenueCat =>
      revenueCatIosKey.isNotEmpty || revenueCatAndroidKey.isNotEmpty;

  /// Plain-language status for logs and debug screens.
  static Map<String, Object?> get summary => {
    'onlineSync': hasApi,
    'storeBilling': hasRevenueCat,
    'analytics': analyticsEnabled && hasApi,
  };
}
