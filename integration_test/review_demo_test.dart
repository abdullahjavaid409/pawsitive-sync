// The App Review demo: one take, typed by hand, paced to be read. Shows the
// guard (the reason the app exists), "not sure if given", and a sitter
// logging from a browser link. scripts/review_demo.sh records the simulator
// and reacts to the "[demo] …" lines below.
//
// Run against a QA backend, never production:
//   scripts/review_demo.sh
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pawsitive_sync/core/config/app_config.dart';
import 'package:pawsitive_sync/core/logging/app_log.dart';
import 'package:pawsitive_sync/data/care_repository.dart';
import 'package:pawsitive_sync/domain/models.dart';
import 'package:pawsitive_sync/main.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/qa.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    expect(AppConfig.apiBaseUrl.contains('production'), isFalse);
  });

  testWidgets('app review demo', (t) async {
    final qa = Qa(t);
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    AppLog.enableTestCapture();
    await t.pumpWidget(await bootstrap());
    await qa.settle(2000);

    // Real time, so the recording shows each screen long enough to read.
    Future<void> hold(double seconds) async {
      final end = DateTime.now().add(
        Duration(milliseconds: (seconds * 1000).round()),
      );
      while (DateTime.now().isBefore(end)) {
        await t.pump(const Duration(milliseconds: 50));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    }

    CareRepository care() => Provider.of<CareRepository>(
      t.element(find.byType(Scaffold).first),
      listen: false,
    );

    // Jump, not animate: integration-test frames only advance on pump.
    Future<void> toTop() async {
      for (final e in find.byType(Scrollable).evaluate()) {
        final state = (e as StatefulElement).state as ScrollableState;
        if (state.position.axis == Axis.vertical) state.position.jumpTo(0);
      }
      await qa.settle(600);
    }

    debugPrint('[demo] start');
    await hold(3.5);

    // 1. No account: straight into setup.
    await qa.tap(find.text('Get started'));
    await qa.type(find.byType(TextFormField), 'Miso');
    await hold(1);
    await qa.tap(find.text('Continue'));
    // v14 setup: the first medicine is added after Pro below, so skip it.
    await qa.tap(find.text('Skip'));
    await qa.tap(find.text('Continue'));
    await qa.tap(find.text('Not now'));
    await qa.tap(find.text('Go to Today'));
    await hold(2.5);
    await qa.tap(find.text('Continue free with 1 pet'));

    // Debug-only stand-in for RevenueCat's entitlement listener (as in the
    // integration tests); release builds only get Pro from RevenueCat.
    care().applyStoreEntitlement(true, BillingPlan.yearly);
    await qa.settle(1200);

    // 2. A real routine: insulin twice a day, plus a morning tablet.
    Future<void> addMedicine(
      String name,
      String amount, {
      bool evening = false,
    }) async {
      await hold(1.2);
      await qa.addMedicine(name, amount: amount, evening: evening);
      await qa.settle(2000);
    }

    await qa.tap(find.text('Add first medicine'));
    await addMedicine('Insulin', '2 units', evening: true);
    await qa.tap(find.text('Add'));
    await addMedicine('Gabapentin', '100 mg');
    await toTop();
    await hold(3);

    // 3. One tap: "Mark given", confirmed on the sheet.
    await qa.tap(find.text('Mark given'));
    await hold(2);
    await qa.tap(find.text('Confirm given').last);
    await qa.settle(1500);
    await hold(2.5);

    // 4. The guard: trying the same dose again is stopped by name and time.
    await qa.tap(find.text('Insulin').first);
    await qa.see('ALREADY GIVEN');
    await hold(5);
    await qa.tap(find.text('Don’t give it'));
    await hold(1);

    // 5. Not sure if given: the next person is told to check first.
    await qa.tap(find.text('Mark given'));
    await hold(1.5);
    await qa.tap(find.text('Not sure if given'));
    await qa.see('Needs a check', partial: true);
    await hold(3.5);

    // 6. A sitter gets a browser link: no app, no account.
    await qa.tapLabel('Household');
    await qa.tap(find.text('Invite someone'));
    await qa.waitUntil(() => care().inviteCode.isNotEmpty, seconds: 20);
    await hold(2.5);
    // The local QA server checks Pro itself; the script marks this
    // household Pro in the QA database only.
    debugPrint('[demo] server-pro');
    await hold(1.5);
    await qa.type(find.byType(TextField).first, 'Jordan (sitter)');
    await qa.tap(find.text('Share'));
    await qa.tap(find.text('Continue'));
    await qa.tap(find.text('Pet sitter'));
    await qa.tap(find.text('Continue'));
    await hold(1);
    // Creates the link, then opens the iOS share sheet (the script's
    // recording dismisses it).
    await qa.tap(find.text('Share invite'));
    await qa.waitUntil(() => care().sitterLink != null, seconds: 20);
    await hold(2.5);

    debugPrint('[demo] open-url ${care().sitterLink!.url}');
    // The script shows the page in Safari, then brings the app back:
    // wait for the app to leave the foreground, then to return.
    AppLifecycleState? state() => WidgetsBinding.instance.lifecycleState;
    await qa.waitUntil(() => state() != AppLifecycleState.resumed, seconds: 30);
    await qa.waitUntil(() => state() == AppLifecycleState.resumed, seconds: 90);
    await qa.settle(1500);

    // 7. Everything in one record for the vet.
    await qa.tap(find.text('Done'));
    await qa.tapLabel('Reports');
    await toTop();
    await hold(3.5);

    debugPrint('[demo] end');
    await hold(1);
  });
}
