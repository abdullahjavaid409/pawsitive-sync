import 'package:pawsitive_sync/core/config/app_config.dart';

/// RevenueCat billing. Keys live in [AppConfig] — see docs/CONFIG.md.
abstract final class BillingConfig {
  static const iosApiKey = AppConfig.revenueCatIosKey;
  static const androidApiKey = AppConfig.revenueCatAndroidKey;

  static const entitlementId = 'pro';

  static bool get hasApiKey => AppConfig.hasRevenueCat;
}
