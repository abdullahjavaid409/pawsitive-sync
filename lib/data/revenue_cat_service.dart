import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:pawsitive_sync/core/config/billing_config.dart';
import 'package:pawsitive_sync/core/logging/app_log.dart';
import 'package:pawsitive_sync/domain/models.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

enum PurchaseErrorKind {
  cancelled,
  unavailable,
  network,
  entitlementMissing,
  notConfigured,
  unknown,
}

class PurchaseResult {
  const PurchaseResult({
    required this.success,
    this.message,
    this.kind,
  });

  final bool success;
  final String? message;
  final PurchaseErrorKind? kind;
}

/// StoreKit / Play Billing via RevenueCat. Logs every step through [AppLog].
abstract final class RevenueCatService {
  static const _networkTimeout = Duration(seconds: 15);
  static const _purchaseTimeout = Duration(seconds: 45);

  static bool _initialized = false;
  static String? _memberId;
  static List<Package>? _cachedPackages;

  static bool get isReady => _initialized;

  static Future<void> initialize() async {
    if (_initialized) return;
    if (kIsWeb) {
      AppLog.event('billing.rc.skip', {'reason': 'web'});
      return;
    }

    final apiKey = Platform.isIOS
        ? BillingConfig.iosApiKey
        : Platform.isAndroid
        ? BillingConfig.androidApiKey
        : '';

    if (apiKey.isEmpty) {
      AppLog.event('billing.rc.skip', {'reason': 'missing_api_key'});
      return;
    }

    await AppLog.trace('billing.rc.init', () async {
      final config = PurchasesConfiguration(apiKey);
      await Purchases.configure(config);
      Purchases.addCustomerInfoUpdateListener(_onCustomerInfo);
      _initialized = true;
      AppLog.event('billing.rc.ready', {'platform': Platform.operatingSystem});
    });
  }

  static void _onCustomerInfo(CustomerInfo info) {
    final active = info.entitlements.active.containsKey(BillingConfig.entitlementId);
    AppLog.event('billing.rc.customer_updated', {
      'active': active,
      'entitlements': info.entitlements.active.keys.join(','),
    });
  }

  static Future<void> identifyMember(String memberId) async {
    if (!_initialized || memberId.isEmpty) return;
    if (_memberId == memberId) return;
    await AppLog.trace('billing.rc.identify', () async {
      await Purchases.logIn(memberId).timeout(_networkTimeout);
      _memberId = memberId;
      AppLog.event('billing.rc.identified', {'memberId': memberId});
    });
  }

  static Future<void> logOut() async {
    if (!_initialized) return;
    try {
      await Purchases.logOut().timeout(_networkTimeout);
      AppLog.event('billing.rc.logout');
    } catch (error, stack) {
      AppLog.error('billing.rc.logout_failed', error, stack);
    } finally {
      _memberId = null;
      _cachedPackages = null;
    }
  }

  static Future<List<Package>> loadPackages({bool force = false}) async {
    if (!_initialized) return const [];
    if (!force && _cachedPackages != null) return _cachedPackages!;

    return AppLog.trace('billing.rc.load_packages', () async {
      final offerings = await Purchases.getOfferings().timeout(_networkTimeout);
      Offering? offering = offerings.current;
      if (offering == null && offerings.all.isNotEmpty) {
        offering = offerings.all.values.first;
      }
      final packages = offering == null
          ? const <Package>[]
          : offering.availablePackages;
      _cachedPackages = packages;
      AppLog.event('billing.rc.packages_loaded', {
        'count': packages.length,
        'offering': offering?.identifier ?? 'none',
      });
      return packages;
    });
  }

  static Package? packageForPlan(BillingPlan plan, List<Package> packages) {
    if (packages.isEmpty) return null;
    final type = plan == BillingPlan.yearly
        ? PackageType.annual
        : PackageType.monthly;
    for (final package in packages) {
      if (package.packageType == type) return package;
    }
    final needle = plan == BillingPlan.yearly ? 'year' : 'month';
    for (final package in packages) {
      final id = package.storeProduct.identifier.toLowerCase();
      if (id.contains(needle)) return package;
    }
    return packages.first;
  }

  static Future<bool> hasActiveSubscription() async {
    if (!_initialized) return false;
    try {
      final info = await Purchases.getCustomerInfo().timeout(_networkTimeout);
      final active = info.entitlements.active.containsKey(
        BillingConfig.entitlementId,
      );
      AppLog.event('billing.rc.check', {'active': active});
      return active;
    } catch (error, stack) {
      AppLog.error('billing.rc.check_failed', error, stack);
      return false;
    }
  }

  static BillingPlan? planFromStore(CustomerInfo info) {
    final entitlement = info.entitlements.active[BillingConfig.entitlementId];
    if (entitlement == null) return null;
    final id = entitlement.productIdentifier.toLowerCase();
    if (id.contains('year') || id.contains('annual')) {
      return BillingPlan.yearly;
    }
    if (id.contains('month')) return BillingPlan.monthly;
    return null;
  }

  static Future<({bool isPro, BillingPlan? plan})> currentStatus() async {
    if (!_initialized) return (isPro: false, plan: null);
    try {
      final info = await Purchases.getCustomerInfo().timeout(_networkTimeout);
      final isPro = info.entitlements.active.containsKey(
        BillingConfig.entitlementId,
      );
      final plan = isPro ? planFromStore(info) : null;
      AppLog.event('billing.rc.status', {
        'isPro': isPro,
        'plan': plan?.name ?? 'unknown',
      });
      return (isPro: isPro, plan: plan);
    } catch (error, stack) {
      AppLog.error('billing.rc.status_failed', error, stack);
      return (isPro: false, plan: null);
    }
  }

  static Future<PurchaseResult> purchasePlan(BillingPlan plan) async {
    if (!_initialized) {
      AppLog.event('billing.rc.purchase_skipped', {'reason': 'not_configured'});
      return const PurchaseResult(
        success: false,
        kind: PurchaseErrorKind.notConfigured,
        message: 'Purchases are not set up on this build yet.',
      );
    }

    return AppLog.trace('billing.rc.purchase', () async {
      try {
        final packages = await loadPackages();
        final package = packageForPlan(plan, packages);
        if (package == null) {
          AppLog.event('billing.rc.purchase_no_package', {'plan': plan.name});
          return const PurchaseResult(
            success: false,
            kind: PurchaseErrorKind.unavailable,
            message: 'This plan is not available right now. Try again later.',
          );
        }

        AppLog.event('billing.rc.purchase_start', {
          'plan': plan.name,
          'productId': package.storeProduct.identifier,
          'price': package.storeProduct.priceString,
        });

        final response = await Purchases.purchase(
          PurchaseParams.package(package),
        ).timeout(_purchaseTimeout);

        final hasPro = response.customerInfo.entitlements.active.containsKey(
          BillingConfig.entitlementId,
        );

        if (hasPro) {
          AppLog.event('billing.rc.purchase_success', {'plan': plan.name});
          return const PurchaseResult(success: true);
        }

        AppLog.event('billing.rc.purchase_no_entitlement', {'plan': plan.name});
        return const PurchaseResult(
          success: false,
          kind: PurchaseErrorKind.entitlementMissing,
          message:
              'Purchase finished but Pro did not activate. Try Restore or contact support.',
        );
      } on PurchasesError catch (error) {
        return _mapPurchasesError(error);
      } on PlatformException catch (error) {
        return _mapPlatformError(error);
      } on TimeoutException {
        AppLog.event('billing.rc.purchase_timeout');
        return const PurchaseResult(
          success: false,
          kind: PurchaseErrorKind.network,
          message: 'Purchase timed out. Check your connection and try again.',
        );
      } catch (error, stack) {
        AppLog.error('billing.rc.purchase_failed', error, stack);
        return PurchaseResult(
          success: false,
          kind: PurchaseErrorKind.unknown,
          message: 'Something went wrong. Please try again.',
        );
      }
    });
  }

  static Future<bool> restorePurchases() async {
    if (!_initialized) {
      AppLog.event('billing.rc.restore_skipped', {'reason': 'not_configured'});
      return false;
    }

    return AppLog.trace('billing.rc.restore', () async {
      try {
        final info = await Purchases.restorePurchases().timeout(
          _purchaseTimeout,
        );
        final active = info.entitlements.active.containsKey(
          BillingConfig.entitlementId,
        );
        AppLog.event('billing.rc.restore_done', {'active': active});
        return active;
      } catch (error, stack) {
        AppLog.error('billing.rc.restore_failed', error, stack);
        return false;
      }
    });
  }

  static PurchaseResult _mapPurchasesError(PurchasesError error) {
    AppLog.event('billing.rc.purchase_error', {
      'code': error.code.name,
      'message': error.message,
    });
    return switch (error.code) {
      PurchasesErrorCode.purchaseCancelledError => const PurchaseResult(
        success: false,
        kind: PurchaseErrorKind.cancelled,
      ),
      PurchasesErrorCode.networkError => const PurchaseResult(
        success: false,
        kind: PurchaseErrorKind.network,
        message: 'Network error. Check your connection and try again.',
      ),
      PurchasesErrorCode.productNotAvailableForPurchaseError ||
      PurchasesErrorCode.configurationError => const PurchaseResult(
        success: false,
        kind: PurchaseErrorKind.unavailable,
        message: 'This plan is not available right now.',
      ),
      _ => PurchaseResult(
        success: false,
        kind: PurchaseErrorKind.unknown,
        message: error.message,
      ),
    };
  }

  static PurchaseResult _mapPlatformError(PlatformException error) {
    AppLog.event('billing.rc.platform_error', {
      'code': error.code,
      'message': error.message ?? '',
    });
    final cancelled =
        error.code == '1' ||
        (error.message?.toLowerCase().contains('cancel') ?? false);
    if (cancelled) {
      return const PurchaseResult(
        success: false,
        kind: PurchaseErrorKind.cancelled,
      );
    }
    return PurchaseResult(
      success: false,
      kind: PurchaseErrorKind.unknown,
      message: error.message ?? 'Purchase failed.',
    );
  }
}
