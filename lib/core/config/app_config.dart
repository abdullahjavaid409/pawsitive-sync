/// One place for app settings. Everything here has a safe default — no keys required to run.
abstract final class AppConfig {
  /// Household sync server. Empty = fully offline (pets and doses stay on this phone).
  static const apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://pawsitive-api-production.up.railway.app',
  );

  /// RevenueCat iOS public key. Empty = Pro trial works locally; store purchases need a key.
  static const revenueCatIosKey = String.fromEnvironment('REVENUECAT_IOS_KEY');

  /// RevenueCat Android public key. Empty = same as iOS — local trial only.
  static const revenueCatAndroidKey = String.fromEnvironment(
    'REVENUECAT_ANDROID_KEY',
  );

  /// Anonymous usage counts (no names, no pets). Off when API is empty.
  static const analyticsEnabled = bool.fromEnvironment(
    'ANALYTICS_ENABLED',
    defaultValue: true,
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
