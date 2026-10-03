import 'package:flutter_test/flutter_test.dart';
import 'package:pawsitive_sync/core/legal/subscription_disclosure.dart';
import 'package:pawsitive_sync/domain/models.dart';

void main() {
  test('mentions a trial only when the user gets one', () {
    expect(
      SubscriptionDisclosure.compactLine(
        BillingPlan.yearly,
        price: '\$29.99',
        trialDays: 7,
      ),
      startsWith('7-day free trial, then \$29.99/year.'),
    );
    expect(
      SubscriptionDisclosure.compactLine(BillingPlan.monthly, price: '\$4.99'),
      startsWith('\$4.99/month.'),
    );
  });

  test('fallback trial matches App Store Connect: yearly only', () {
    expect(SubscriptionDisclosure.fallbackTrialDays(BillingPlan.yearly), 7);
    expect(SubscriptionDisclosure.fallbackTrialDays(BillingPlan.monthly), isNull);
  });
}
