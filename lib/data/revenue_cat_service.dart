import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:pawsitive_sync/core/config/billing_config.dart';
import 'package:pawsitive_sync/core/logging/app_log.dart';
import 'package:pawsitive_sync/domain/models.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:purchases_ui_flutter/purchases_ui_flutter.dart';

enum PurchaseErrorKind {
  cancelled,
  unavailable,
  network,
  entitlementMissing,
  notConfigured,

  /// Ask to Buy or bank approval — Pro unlocks via the listener when approved.
  pending,

  /// This Apple ID already owns it — restore instead of buying again.
  alreadyOwned,

  /// Screen Time / parental controls block purchases on this device.
  notAllowed,
  unknown,
}

/// One plan as the store sells it to this user — real localized prices and
/// whether *this* user can still get the free trial.
class PlanOffer {
  const PlanOffer({
    required this.package,
    required this.priceString,
    required this.price,
    this.perMonthString,
    this.trialDays,
  });

  final Package package;
  final String priceString;
  final double price;
  final String? perMonthString;

  /// Free-trial length when the user is eligible; null when there is no trial
  /// or they already used it. Drives honest CTA and disclosure copy.
  final int? trialDays;

  bool get hasTrial => trialDays != null;
}

/// What a paywall placement should show. [metadata] comes from the RevenueCat
/// offering so copy can be A/B tested from the dashboard without a release.
class PaywallOffer {
  const PaywallOffer({
    required this.offeringId,
    required this.packages,
    this.yearly,
    this.monthly,
    this.metadata = const {},
  });

  final String offeringId;
  final List<Package> packages;
  final PlanOffer? yearly;
  final PlanOffer? monthly;
  final Map<String, Object> metadata;

  PlanOffer? forPlan(BillingPlan plan) =>
      plan == BillingPlan.yearly ? yearly : monthly;

  /// Real savings of yearly vs 12× monthly, rounded down so the badge never
  /// overstates it. Null when either price is missing.
  int? get yearlySavingsPercent {
    final y = yearly?.price;
    final m = monthly?.price;
    if (y == null || m == null || m <= 0) return null;
    final pct = ((1 - y / (m * 12)) * 100).floor();
    return pct > 0 ? pct : null;
  }

  String? text(String key) {
    final value = metadata[key];
    return value is String && value.trim().isNotEmpty ? value.trim() : null;
  }
}

class PurchaseResult {
  const PurchaseResult({required this.success, this.message, this.kind});

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
  static final Map<String, PaywallOffer> _offerCache = {};
  static Map<String, String> _sentAttributes = const {};

  static bool get isReady => _initialized;

  /// Called whenever the store's view of Pro changes while the app runs:
  /// a purchase that finishes after our timeout, Ask to Buy approval,
  /// renewal, expiry, refund. [CareRepository] wires this at launch.
  static void Function(bool isPro, BillingPlan? plan)? onEntitlementChanged;
  static bool? _lastActive;

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

    // Never throw: launch must work offline and through a RevenueCat outage.
    // Billing stays off for this session; dose logging is unaffected.
    try {
      await AppLog.trace('billing.rc.init', () async {
        final config = PurchasesConfiguration(apiKey);
        await Purchases.configure(config);
        Purchases.addCustomerInfoUpdateListener(_onCustomerInfo);
        _initialized = true;
        AppLog.event('billing.rc.ready', {
          'platform': Platform.operatingSystem,
        });
      });
    } catch (error, stack) {
      AppLog.error('billing.rc.init_failed', error, stack);
    }
  }

  static void _onCustomerInfo(CustomerInfo info) {
    final active = info.entitlements.active.containsKey(
      BillingConfig.entitlementId,
    );
    AppLog.event('billing.rc.customer_updated', {
      'active': active,
      'entitlements': info.entitlements.active.keys.join(','),
    });
    if (_lastActive == active) return;
    _lastActive = active;
    try {
      onEntitlementChanged?.call(active, active ? planFromStore(info) : null);
    } catch (error, stack) {
      AppLog.error('billing.rc.entitlement_handler_failed', error, stack);
    }
  }

  /// Older builds logged every owner in as 'you', one store account shared by
  /// strangers. Send those phones back to their own anonymous id.
  static const _legacySharedId = 'you';

  static Future<void> identifyMember(String memberId) async {
    if (!_initialized) return;
    if (memberId.isEmpty || memberId == _legacySharedId) {
      try {
        final current = await Purchases.appUserID.timeout(_networkTimeout);
        if (current == _legacySharedId) await logOut();
      } catch (error, stack) {
        AppLog.error('billing.rc.legacy_check_failed', error, stack);
      }
      return;
    }
    if (_memberId == memberId) return;
    // Offline or slow network: keep the cached identity and retry on the next
    // resume. Throwing here would block app launch.
    try {
      await AppLog.trace('billing.rc.identify', () async {
        await Purchases.logIn(memberId).timeout(_networkTimeout);
        _memberId = memberId;
        _offerCache.clear();
        AppLog.event('billing.rc.identified', {'memberId': memberId});
      });
    } catch (error, stack) {
      AppLog.error('billing.rc.identify_failed', error, stack);
    }
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
      _offerCache.clear();
      _sentAttributes = const {};
    }
  }

  static Future<List<Package>> loadPackages({bool force = false}) async {
    if (!_initialized) return const [];
    if (!force && _cachedPackages != null) return _cachedPackages!;

    try {
      return await _loadPackages();
    } catch (error, stack) {
      AppLog.error('billing.rc.load_packages_failed', error, stack);
      return const [];
    }
  }

  static Future<List<Package>> _loadPackages() {
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

  /// Offering for a paywall moment. RevenueCat Targeting can serve a
  /// different offering per placement (price test, copy test, country), and
  /// falls back to the current offering when no rule matches.
  static Future<PaywallOffer?> loadOffer(String placement) async {
    if (!_initialized) return null;
    final cached = _offerCache[placement];
    if (cached != null) return cached;

    try {
      return await AppLog.trace('billing.rc.load_offer', () async {
        Offering? offering = await Purchases.getCurrentOfferingForPlacement(
          placement,
        ).timeout(_networkTimeout);
        if (offering == null) {
          final offerings = await Purchases.getOfferings().timeout(
            _networkTimeout,
          );
          offering = offerings.current;
        }
        if (offering == null) return null;

        final packages = offering.availablePackages;
        final yearlyPackage = _matchPackage(BillingPlan.yearly, packages);
        final monthlyPackage = _matchPackage(BillingPlan.monthly, packages);
        final eligibility = await _trialEligibility([
          ?yearlyPackage?.storeProduct,
          ?monthlyPackage?.storeProduct,
        ]);

        final offer = PaywallOffer(
          offeringId: offering.identifier,
          packages: packages,
          yearly: _planOffer(yearlyPackage, eligibility),
          monthly: _planOffer(monthlyPackage, eligibility),
          metadata: offering.metadata,
        );
        _offerCache[placement] = offer;
        AppLog.event('billing.rc.offer_loaded', {
          'placement': placement,
          'offering': offer.offeringId,
          'yearlyTrial': offer.yearly?.trialDays ?? 0,
          'monthlyTrial': offer.monthly?.trialDays ?? 0,
        });
        return offer;
      });
    } catch (error, stack) {
      AppLog.error('billing.rc.load_offer_failed', error, stack);
      return null;
    }
  }

  static PlanOffer? _planOffer(Package? package, Map<String, bool> eligible) {
    if (package == null) return null;
    final product = package.storeProduct;
    return PlanOffer(
      package: package,
      priceString: product.priceString,
      price: product.price,
      perMonthString: product.pricePerMonthString,
      trialDays: eligible[product.identifier] == false
          ? null
          : _trialDays(product),
    );
  }

  /// Days of free trial the store attached to [product], or null.
  static int? _trialDays(StoreProduct product) {
    final intro = product.introductoryPrice;
    if (intro != null && intro.price == 0) {
      return _days(intro.periodUnit, intro.periodNumberOfUnits * intro.cycles);
    }
    // Play only returns offers the user is eligible for.
    final period = product.defaultOption?.freePhase?.billingPeriod;
    if (period != null) return _days(period.unit, period.value);
    return null;
  }

  static int? _days(PeriodUnit unit, int count) => switch (unit) {
    PeriodUnit.day => count,
    PeriodUnit.week => count * 7,
    PeriodUnit.month => count * 30,
    PeriodUnit.year => count * 365,
    PeriodUnit.unknown => null,
  };

  /// iOS: asks StoreKit whether this Apple ID already used the intro offer.
  /// Unknown counts as eligible — Apple then decides at checkout.
  static Future<Map<String, bool>> _trialEligibility(
    List<StoreProduct> products,
  ) async {
    if (products.isEmpty || !Platform.isIOS) return const {};
    try {
      final result = await Purchases.checkTrialOrIntroductoryPriceEligibility(
        products.map((p) => p.identifier).toList(),
      ).timeout(_networkTimeout);
      return {
        for (final entry in result.entries)
          entry.key:
              entry.value.status !=
              IntroEligibilityStatus.introEligibilityStatusIneligible,
      };
    } catch (error, stack) {
      AppLog.error('billing.rc.eligibility_failed', error, stack);
      return const {};
    }
  }

  /// Segments for RevenueCat Audiences, Targeting and Experiment breakdowns.
  /// Counts and flags only — never pet names or emails. RevenueCat batches
  /// attribute uploads itself; this only skips unchanged values.
  static Future<void> syncAttributes(Map<String, String> attributes) async {
    if (!_initialized) return;
    final changed = {
      for (final entry in attributes.entries)
        if (_sentAttributes[entry.key] != entry.value) entry.key: entry.value,
    };
    if (changed.isEmpty) return;
    try {
      await Purchases.setAttributes(changed);
      _sentAttributes = {..._sentAttributes, ...changed};
      AppLog.event('billing.rc.attributes', {'keys': changed.keys.join(',')});
    } catch (error, stack) {
      AppLog.error('billing.rc.attributes_failed', error, stack);
    }
  }

  static Package? packageForPlan(BillingPlan plan, List<Package> packages) =>
      _matchPackage(plan, packages) ??
      (packages.isEmpty ? null : packages.first);

  static Package? _matchPackage(BillingPlan plan, List<Package> packages) {
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
    return null;
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

  /// Buys [plan]. Pass [package] from the [PaywallOffer] on screen so the
  /// purchase matches the placement's offering and is attributed to it.
  static Future<PurchaseResult> purchasePlan(
    BillingPlan plan, {
    Package? package,
  }) async {
    if (!_initialized) {
      AppLog.event('billing.rc.purchase_skipped', {'reason': 'not_configured'});
      return const PurchaseResult(
        success: false,
        kind: PurchaseErrorKind.notConfigured,
        message: 'Purchases aren’t available right now. Try again later.',
      );
    }

    return AppLog.trace('billing.rc.purchase', () async {
      try {
        final chosen = package ?? packageForPlan(plan, await loadPackages());
        if (chosen == null) {
          AppLog.event('billing.rc.purchase_no_package', {'plan': plan.name});
          return const PurchaseResult(
            success: false,
            kind: PurchaseErrorKind.unavailable,
            message: 'This plan is not available right now. Try again later.',
          );
        }

        AppLog.event('billing.rc.purchase_start', {
          'plan': plan.name,
          'productId': chosen.storeProduct.identifier,
          'price': chosen.storeProduct.priceString,
          'offering': chosen.presentedOfferingContext.offeringIdentifier,
        });

        final response = await Purchases.purchase(
          PurchaseParams.package(chosen),
        ).timeout(_purchaseTimeout);

        final hasPro = response.customerInfo.entitlements.active.containsKey(
          BillingConfig.entitlementId,
        );

        if (hasPro) {
          // Trial eligibility changed; next paywall must re-ask the store.
          _offerCache.clear();
          AppLog.event('billing.rc.purchase_success', {'plan': plan.name});
          return const PurchaseResult(success: true);
        }

        AppLog.event('billing.rc.purchase_no_entitlement', {'plan': plan.name});
        return const PurchaseResult(
          success: false,
          kind: PurchaseErrorKind.entitlementMissing,
          message: 'Purchase finished but Pro did not activate. Try Restore or contact support.',
        );
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

  /// true = Pro restored, false = nothing to restore, null = store unreachable.
  static Future<bool?> restorePurchases() async {
    if (!_initialized) {
      AppLog.event('billing.rc.restore_skipped', {'reason': 'not_configured'});
      return null;
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
        return null;
      }
    });
  }

  /// RevenueCat Customer Center: manage plan, cancel with a feedback survey
  /// and a retention offer, refund requests, restore. Returns false when the
  /// SDK is not configured so callers can fall back to Apple's settings page.
  static Future<bool> presentCustomerCenter() async {
    if (!_initialized) {
      AppLog.event('billing.rc.customer_center_skipped');
      return false;
    }
    try {
      AppLog.event('billing.rc.customer_center_open');
      await RevenueCatUI.presentCustomerCenter(
        onRefundRequestCompleted: (productId, status) => AppLog.event(
          'billing.rc.refund_request',
          {'productId': productId, 'status': status},
        ),
        onFeedbackSurveyCompleted: (optionId) =>
            AppLog.event('billing.rc.cancel_survey', {'option': optionId}),
        onPromotionalOfferSucceeded: (_, _, _) {
          _offerCache.clear();
          AppLog.event('billing.rc.retention_offer_accepted');
        },
      );
      return true;
    } catch (error, stack) {
      AppLog.error('billing.rc.customer_center_failed', error, stack);
      return false;
    }
  }

  /// The SDK reports every store failure as a [PlatformException]; map its
  /// code to copy the user can act on. Every branch is logged.
  @visibleForTesting
  static PurchaseResult mapPlatformErrorForTest(PlatformException error) =>
      _mapPlatformError(error);

  /// SDK helper throws on a non-numeric code, which would escape our catch
  /// and leave the paywall spinner stuck. Parse defensively instead.
  static PurchasesErrorCode _codeOf(PlatformException error) {
    final raw = int.tryParse(error.code);
    if (raw == null || raw < 0 || raw >= PurchasesErrorCode.values.length) {
      return PurchasesErrorCode.unknownError;
    }
    return PurchasesErrorCode.values[raw];
  }

  static PurchaseResult _mapPlatformError(PlatformException error) {
    final code = _codeOf(error);
    AppLog.event('billing.rc.purchase_error', {
      'code': code.name,
      'message': error.message ?? '',
    });
    return switch (code) {
      PurchasesErrorCode.purchaseCancelledError => const PurchaseResult(
        success: false,
        kind: PurchaseErrorKind.cancelled,
      ),
      PurchasesErrorCode.paymentPendingError => const PurchaseResult(
        success: false,
        kind: PurchaseErrorKind.pending,
        message: 'Waiting for approval. Pro turns on automatically once it goes through.',
      ),
      PurchasesErrorCode.productAlreadyPurchasedError ||
      PurchasesErrorCode.receiptAlreadyInUseError ||
      PurchasesErrorCode.receiptInUseByOtherSubscriberError =>
        const PurchaseResult(
          success: false,
          kind: PurchaseErrorKind.alreadyOwned,
          message: 'This Apple ID already has Pro. Tap Restore to turn it on.',
        ),
      PurchasesErrorCode.purchaseNotAllowedError ||
      PurchasesErrorCode.insufficientPermissionsError => const PurchaseResult(
        success: false,
        kind: PurchaseErrorKind.notAllowed,
        message: 'Purchases are turned off on this device. Check Screen Time settings.',
      ),
      PurchasesErrorCode.networkError ||
      PurchasesErrorCode.offlineConnectionError => const PurchaseResult(
        success: false,
        kind: PurchaseErrorKind.network,
        message: 'No connection. Check your internet and try again.',
      ),
      PurchasesErrorCode.operationAlreadyInProgressError =>
        const PurchaseResult(
          success: false,
          kind: PurchaseErrorKind.pending,
          message: 'A purchase is already in progress.',
        ),
      PurchasesErrorCode.productNotAvailableForPurchaseError ||
      PurchasesErrorCode.configurationError ||
      PurchasesErrorCode.ineligibleError => const PurchaseResult(
        success: false,
        kind: PurchaseErrorKind.unavailable,
        message: 'This plan is not available right now. Try again later.',
      ),
      PurchasesErrorCode.storeProblemError => const PurchaseResult(
        success: false,
        kind: PurchaseErrorKind.unknown,
        message:
            'The App Store had a problem. You were not charged — try again.',
      ),
      _ => const PurchaseResult(
        success: false,
        kind: PurchaseErrorKind.unknown,
        message: 'Something went wrong. You were not charged — try again.',
      ),
    };
  }
}
