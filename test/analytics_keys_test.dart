import 'package:flutter_test/flutter_test.dart';
import 'package:pawsitive_sync/data/analytics_service.dart';

void main() {
  test('funnel events count as is; others are ignored', () {
    expect(
      AnalyticsService.keyFor('dose.log.completed', const {}),
      'dose.log.completed',
    );
    expect(AnalyticsService.keyFor('billing.trial.tap', const {}), isNotNull);
    expect(AnalyticsService.keyFor('pet.add.completed', const {}), isNull);
  });

  test('paywall views and onboarding steps split by where', () {
    expect(
      AnalyticsService.keyFor('billing.paywall.opened', const {
        'placement': 'invite',
      }),
      'billing.paywall.opened.invite',
    );
    expect(
      AnalyticsService.keyFor('onboarding.step', const {'step': 'pet_basics'}),
      'onboarding.step.pet_basics',
    );
    // Free text never reaches the server as a name.
    expect(
      AnalyticsService.keyFor('billing.paywall.opened', const {
        'placement': 'Miso the cat',
      }),
      'billing.paywall.opened.other',
    );
    expect(
      AnalyticsService.keyFor('onboarding.step', const {}),
      'onboarding.step.unknown',
    );
  });
}
