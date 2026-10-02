import 'package:pawsitive_sync/domain/models.dart';

/// Apple Guideline 3.1.2 — subscription terms shown before purchase.
abstract final class SubscriptionDisclosure {
  static String trialLine(BillingPlan plan) {
    return plan == BillingPlan.yearly
        ? '7-day free trial, then \$29.99 per year (\$2.50/month).'
        : '7-day free trial, then \$4.99 per month.';
  }

  /// One line for the paywall footer (Apple 3.1.2 essentials).
  static String compactLine(BillingPlan plan) {
    final price = plan == BillingPlan.yearly
        ? '\$29.99/year after trial'
        : '\$4.99/month after trial';
    return '7-day free trial, then $price. Auto-renews; cancel in Apple ID → Subscriptions.';
  }

  static const autoRenew = '''
Payment is charged to your Apple ID at the end of the trial. Subscription renews automatically unless canceled at least 24 hours before the end of the current period. Your account is charged for renewal within 24 hours prior to the end of the period. You can manage or cancel anytime in Settings → Apple ID → Subscriptions after purchase.''';

  static const freeTier =
      'Free includes one pet and local reminders. Pro unlocks every pet, household invites, low-supply alerts, and vet reports.';
}
