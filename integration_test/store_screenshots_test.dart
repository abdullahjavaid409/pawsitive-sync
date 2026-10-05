// Sets the app up like a real household (typed by hand, no demo button) and
// pauses on each App Store screen. scripts/store_screenshots.sh watches for
// the "[shot] name" lines and captures the simulator, status bar included.
//
// Run against a QA backend, never production:
//   scripts/store_screenshots.sh
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pawsitive_sync/core/config/app_config.dart';
import 'package:pawsitive_sync/core/logging/app_log.dart';
import 'package:pawsitive_sync/data/care_repository.dart';
import 'package:pawsitive_sync/data/household_api.dart';
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

  testWidgets('store screenshots', (t) async {
    final qa = Qa(t);
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    AppLog.enableTestCapture();
    await t.pumpWidget(await bootstrap());
    await qa.settle(2500);

    Future<void> shot(String name) async {
      FocusManager.instance.primaryFocus?.unfocus();
      await qa.settle(1200);
      debugPrint('[shot] $name');
      // Real time, so the watcher script can capture before we move on.
      for (var i = 0; i < 40; i++) {
        await t.pump(const Duration(milliseconds: 50));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    }

    Future<void> toTop() async {
      for (final e in find.byType(Scrollable).evaluate()) {
        final state = (e as StatefulElement).state as ScrollableState;
        if (state.position.axis == Axis.vertical) state.position.jumpTo(0);
      }
      await qa.settle(800);
    }

    Future<void> alignTop(Finder target) async {
      await qa.waitFor(target);
      await Scrollable.ensureVisible(t.element(target.first));
      await qa.settle(800);
    }

    // Phones show a bottom bar; wide windows (iPad) show a NavigationRail.
    Future<void> tab(String label) async {
      final rail = find.byType(NavigationRail);
      if (rail.evaluate().isEmpty) return qa.tapLabel(label);
      await qa.tap(find.descendant(of: rail, matching: find.text(label)));
    }

    CareRepository care() => Provider.of<CareRepository>(
      t.element(find.byType(Scaffold).first),
      listen: false,
    );

    Future<void> addMedicine(
      String name,
      String amount, {
      bool evening = false,
      bool morning = true,
      int? supply,
    }) async {
      await qa.type(find.widgetWithText(TextField, 'e.g. Apoquel'), name);
      await qa.type(
        find.widgetWithText(TextField, 'e.g. 1 tablet or 2 units'),
        amount,
      );
      if (!morning) await qa.tap(find.text('Morning'));
      if (evening) await qa.tap(find.text('Evening'));
      if (supply != null) {
        await qa.tap(find.text('Track remaining doses'));
        await qa.type(find.widgetWithText(TextField, 'e.g. 30'), '$supply');
      }
      await qa.tap(find.text('Save medicine'));
      await qa.settle(2500);
    }

    await shot('welcome');

    // Onboarding, typed the way a new owner would.
    await qa.tap(find.text('Get started'));
    await qa.type(find.byType(TextFormField), 'Miso');
    await shot('onboarding_pet');
    await qa.tap(find.text('Continue'));
    await qa.type(find.byType(TextFormField).last, '4.6');
    await qa.tap(find.text('Continue'));
    await qa.tap(find.text('Diabetes'));
    await shot('onboarding_conditions');
    await qa.tap(find.text('Continue with 1 selected'));
    await qa.tap(find.text('Continue'));
    await qa.tap(find.text('Not now'));
    await shot('paywall');
    await qa.tap(find.text('Continue free with 1 pet'));
    // Pro only comes from RevenueCat; stand in for its entitlement listener.
    care().applyStoreEntitlement(true, BillingPlan.yearly);
    await qa.settle(1500);

    // Miso: insulin twice a day, supply running low.
    await qa.tap(find.text('Add first medicine'));
    await addMedicine('Insulin', '2 units', evening: true, supply: 6);

    // Second pet: Biscuit the dog.
    await tab('Pets');
    await qa.tap(find.byTooltip('Add pet'));
    await qa.type(find.widgetWithText(TextField, 'Pet name'), 'Biscuit');
    await qa.tap(find.text('Dog'));
    await qa.tap(find.text('Save pet'));
    // The "Biscuit was added" SnackBar offers the next step directly.
    await qa.tap(find.text('Add medicine'));
    await addMedicine('Apoquel', '1 tablet');
    await qa.gone('Apoquel is on Biscuit’s Today list.', seconds: 10);
    await tab('Today');
    await qa.tap(find.text('Add'));
    await qa.tap(find.text('Biscuit'));
    await addMedicine('Gabapentin', '100 mg', morning: false, evening: true);

    // Household goes online; a partner joins from her own phone.
    await tab('Household');
    await qa.tap(find.text('Invite someone'));
    await qa.waitUntil(() => care().inviteCode.isNotEmpty, seconds: 20);
    await shot('invite');
    final partner = HouseholdApi(Uri.parse(AppConfig.apiBaseUrl));
    final session = await partner.join(code: care().inviteCode, name: 'Sara');
    partner.token = session.token;
    await qa.tap(find.byTooltip('Back'));

    final meds = session.snapshot.medications;
    Future<void> logAs(
      HouseholdApi api,
      HouseholdSession who,
      String med,
      String amount,
      String time,
    ) => api.logDose(
      DoseRecord(
        id: newId('log'),
        medicationId: meds.firstWhere((m) => m.name == med).id,
        part: DayPart.morning,
        day: dayKey(DateTime.now()),
        memberId: who.snapshot.memberId,
        outcome: LogOutcome.given,
        amount: amount,
        timeLabel: time,
      ),
    );
    await logAs(partner, session, 'Insulin', '2 units', '8:02 AM');

    // A sitter joins too and covers Biscuit’s morning tablet.
    final sitter = HouseholdApi(Uri.parse(AppConfig.apiBaseUrl));
    final sitterSession = await sitter.join(
      code: care().inviteCode,
      name: 'Alex',
    );
    sitter.token = sitterSession.token;
    await logAs(sitter, sitterSession, 'Apoquel', '1 tablet', '7:45 AM');

    // Pull everyone’s doses in.
    await tab('Today');
    await qa.pullToRefresh();
    await qa.settle(2500);
    await toTop();
    await shot('today');
    await alignTop(find.text('Today’s schedule'));
    await shot('today_schedule');

    // The safety moment: trying Miso’s insulin again names who gave it.
    await qa.tap(find.textContaining('Insulin · ').first);
    await qa.settle(1500);
    await shot('guard');
    await qa.tap(find.text("Got it, don’t log"));

    await tab('Household');
    await toTop();
    await shot('household');

    await tab('Pets');
    await toTop();
    await shot('pets');

    await tab('Reports');
    await toTop();
    await shot('reports');

    await tab('Today');
    await toTop();
    await qa.tap(find.text('Refill'));
    await toTop();
    await shot('medicine_low');
  });
}
