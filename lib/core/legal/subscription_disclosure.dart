import 'package:pawsitive_sync/domain/models.dart';

/// Apple Guideline 3.1.2 — subscription terms shown before purchase.
abstract final class SubscriptionDisclosure {
  /// Fallback store prices when RevenueCat is not configured (debug/QA).
  /// Release builds always show the store's localized price.
  static String fallbackPrice(BillingPlan plan) =>
      plan == BillingPlan.yearly ? '\$29.99' : '\$4.99';

  /// Only yearly carries the intro offer in App Store Connect.
  static int? fallbackTrialDays(BillingPlan plan) =>
      plan == BillingPlan.yearly ? 7 : null;

  static String period(BillingPlan plan) =>
      plan == BillingPlan.yearly ? 'year' : 'month';

  /// One line for the paywall footer (Apple 3.1.2 essentials). Mentions a
  /// trial only when this user will actually get one.
  static String compactLine(
    BillingPlan plan, {
    required String price,
    int? trialDays,
  }) {
    final renew = 'Auto-renews; cancel in Apple ID → Subscriptions.';
    if (trialDays == null) return '$price/${period(plan)}. $renew';
    return '$trialDays-day free trial, then $price/${period(plan)}. $renew';
  }

  static const autoRenew = '''
Payment is charged to your Apple ID at confirmation of purchase, or at the end of the free trial if one applies. Subscription renews automatically unless canceled at least 24 hours before the end of the current period. Your account is charged for renewal within 24 hours prior to the end of the period. You can manage or cancel anytime in Settings → Apple ID → Subscriptions after purchase.''';

  static const freeTier =
      'Free: one pet, dose logging, double-dose safety, and reminders. '
      'Pro: up to 10 pets, household invites, low-supply alerts, and vet report export.';
}
