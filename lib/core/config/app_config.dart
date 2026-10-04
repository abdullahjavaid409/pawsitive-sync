import 'package:flutter/foundation.dart' show kReleaseMode;

/// One place for app settings. Everything here has a safe default — no keys required to run.
abstract final class AppConfig {
  static const _productionApi = 'https://pawsitive-api-production.up.railway.app';

  /// Household sync server. Empty = fully offline (pets and doses stay on this phone).
  /// Only release builds default to production, so debug runs never write real data.
  static const apiBaseUrl = bool.hasEnvironment('API_BASE_URL')
      ? String.fromEnvironment('API_BASE_URL')
      : (kReleaseMode ? _productionApi : '');

  /// RevenueCat iOS public key. Empty = Pro trial works locally; store purchases need a key.
  /// Automated QA only (`--dart-define=QA_LOCAL_PRO=true`): the paywall
  /// unlocks Pro without a store so test runs can cover Pro flows. Never set
  /// for builds people use — normal debug and release go through the store.
  static const qaLocalPro = bool.fromEnvironment('QA_LOCAL_PRO');

  static const revenueCatIosKey = String.fromEnvironment('REVENUECAT_IOS_KEY');

  /// RevenueCat Android public key. Empty = same as iOS — local trial only.
  static const revenueCatAndroidKey = String.fromEnvironment(
    'REVENUECAT_ANDROID_KEY',
  );

  /// Anonymous usage counts (no names, no pets). Off when API is empty.
  static const analyticsEnabled = bool.fromEnvironment(
    'ANALYTICS_ENABLED',
    defaultValue: kReleaseMode,
  );

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
