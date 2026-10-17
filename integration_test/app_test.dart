// Run against a QA backend, never production:
//   flutter test integration_test/app_test.dart -d <simulator> \
//     --dart-define=API_BASE_URL=http://127.0.0.1:3100
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pawsitive_sync/core/config/app_config.dart';
import 'package:pawsitive_sync/core/logging/app_log.dart';
import 'package:pawsitive_sync/data/care_repository.dart';
import 'package:pawsitive_sync/data/household_api.dart';
import 'package:pawsitive_sync/data/household_store.dart';
import 'package:pawsitive_sync/data/local_database.dart';
import 'package:pawsitive_sync/data/secure_tokens.dart';
import 'package:pawsitive_sync/domain/models.dart';
import 'package:pawsitive_sync/main.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/qa.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    expect(
      AppConfig.apiBaseUrl.contains('production'),
      isFalse,
      reason: 'Point API_BASE_URL at a QA server before running this.',
    );
  });

  testWidgets('free tier: every feature and edge case', (t) async {
    final qa = _qa(t);
    await _launchFresh(qa);

    await qa.step('Welcome opens setup', () async {
      await qa.tap(find.text('Get started'));
      await qa.see('Add your pet’s name to continue');
      qa.event('welcome.continued');
    });

    await qa.step(
      'Edge: blank or whitespace pet name blocks Continue',
      () async {
        await qa.tap(find.text('Continue'));
        await qa.see('Add your pet’s name to continue');
        await qa.type(find.byType(TextFormField), '   ');
        await qa.see('Add your pet’s name to continue');
        qa.noEvent('onboarding.step', {'step': 'pet'});
      },
    );

    await qa.step('Pet step accepts a name', () async {
      await qa.type(find.byType(TextFormField), 'Luna');
      await qa.tap(find.text('Cat'));
      await qa.tap(find.text('Continue'));
      qa.event('onboarding.step', {'step': 'pet'});
    });

    await qa.step('Edge: first medicine needs a name and amount', () async {
      // No red and nothing picked until Continue is tried.
      await qa.tap(find.text('Continue'));
      await qa.see('Still needed: name · form');
      qa.event('onboarding.medicine_blocked');
      await qa.type(find.byType(TextField).first, 'Methimazole');
      await qa.see('Pick the form it comes in.');
      qa.noEvent('onboarding.step', {'step': 'medicine'});
      // Skipped here; the five-step add-medicine flow is tested below.
      await qa.tap(find.text('Skip'));
      qa.event('onboarding.step', {'step': 'medicine', 'skipped': true});
    });

    await qa.step('Household and reminders steps', () async {
      await qa.tap(find.text('Continue'));
      qa.event('onboarding.step', {'step': 'household'});
      await qa.tap(find.text('Not now'));
      qa.event('onboarding.step', {'step': 'notifications', 'ask': false});
      await qa.tap(find.text('Go to Today'));
    });

    await qa.step('Paywall: continue free lands on Today', () async {
      await qa.tap(find.text('Continue free with 1 pet'));
      await qa.see('Today');
      qa.event('billing.continued_free');
      qa.event('billing.paywall.complete', {'isPro': false});
    });

    await qa.step('Edge: medicine flow validation', () async {
      await qa.tap(find.text('Add first medicine'));
      await qa.see('Type a name or pick one from the list');
      await qa.type(
        find.widgetWithText(TextField, 'Search or type a name'),
        'Apoquel',
      );
      await qa.tap(find.text('Continue'));
      await qa.tap(find.text('Continue'));
      await qa.tap(find.text('Continue'));
      await qa.tap(find.text('Morning'));
      await qa.see('Select at least one time of day.');
      await qa.tap(find.text('Morning'));
      await qa.tap(find.text('Track remaining doses'));
      await qa.see('Enter the number of doses left.');
      qa.noEvent('medication.add.completed');
    });

    await qa.step('Pro gate: evening dose time opens paywall', () async {
      await qa.see('Free includes one morning dose', partial: true);
      await qa.tap(find.text('Evening'));
      await qa.see('Morning and evening, both covered');
      qa.event('billing.paywall.opened', {'reason': 'more_dose_times'});
      qa.event('medication.add.blocked', {'reason': 'free_tier_times'});
      await qa.tap(find.byTooltip('Close'));
      // Back on the same step, still morning only, nothing typed lost.
      await qa.see('When does Luna take it?');
      qa.noEvent('medication.add.completed');
    });

    await qa.step(
      'Add medicine with supply tracking (offline write)',
      () async {
        await qa.type(find.byType(TextField).last, '4');
        await qa.tap(find.text('Continue'));
        await qa.tap(find.text('Save medicine'));
        await qa.see('Apoquel is on Luna’s Today list.');
        qa.event('medication.add.completed', {'tracksSupply': true});
      },
    );

    await qa.step(
      'Regression: confirmation SnackBar dismisses by itself',
      () async {
        await qa.gone('Apoquel is on Luna’s Today list.', seconds: 8);
      },
    );

    await qa.step('Not sure if given marks a dose for a check', () async {
      await qa.tap(find.text('Mark given'));
      await qa.see('Log Luna’s Apoquel?');
      await qa.tap(find.text('Not sure if given'));
      await qa.see('Needs a check', partial: true);
      await qa.see('not sure — check first', partial: true);
      qa.event('dose.uncertain.completed');
    });

    await qa.step('Review the unsure dose and log it', () async {
      await qa.tap(find.text('Review dose'));
      await qa.tap(find.text('Confirm given').last);
      await qa.see('Everyone is covered for today');
      qa.event('dose.log.completed');
    });

    await qa.step(
      'Supply count drops; free tier hides low-supply banner',
      () async {
        final apoquel = _care(t).medications.single;
        expect(apoquel.dosesLeft, 3);
        expect(apoquel.isLow, isTrue);
        qa.absent('Refill');
      },
    );

    await qa.step('Safety: double-dose guard blocks a second log', () async {
      await qa.tap(find.text('Apoquel'));
      await qa.see('ALREADY GIVEN');
      await qa.tap(find.text('Don’t give it'));
      qa.event('dose.already');
      expect(qa.count('dose.log.completed'), 1);
    });

    await qa.step('Pro gate: second medicine opens paywall', () async {
      final care = _care(t);
      final petId = care.pets.single.id;
      expect(care.activeMedicationCount(petId), 1);
      expect(care.canAddMedication(petId), isFalse);
      // v14: adding a medicine lives on the pet's page.
      await qa.tapLabel('Pets');
      await qa.tap(find.text('Add medicine'));
      await qa.see('Every medicine, one schedule');
      qa.event('billing.paywall.opened', {'reason': 'more_meds'});
      await qa.tap(find.byTooltip('Close'));
      expect(care.medications, hasLength(1));
      // Logging what’s already scheduled stays free at the cap.
      expect(care.doses.where((d) => d.petId == petId), isNotEmpty);
    });

    await qa.step('Care event add and remove', () async {
      await qa.tap(find.text('Add event'));
      // No type picked yet: Save asks for one instead of guessing.
      await qa.tap(find.text('Save event'));
      await qa.see('Pick the type of care');
      qa.noEvent('care_event.added');
      await qa.tap(find.text('Vet visit'));
      await qa.tap(find.text('Save event'));
      await qa.see('Vet checkup');
      qa.event('care_event.added', {'kind': 'vetVisit'});
      await qa.tap(find.byTooltip('Remove Vet checkup'));
      await qa.tap(find.text('Cancel'));
      await qa.see('Vet checkup');
      qa.noEvent('care_event.removed');
      await qa.tap(find.byTooltip('Remove Vet checkup'));
      await qa.tap(find.text('Remove'));
      await qa.gone('Vet checkup');
      qa.event('care_event.removed');
    });

    await qa.step('Edit pet saves and its SnackBar dismisses', () async {
      await qa.tapLabel('Pets');
      await qa.tap(find.text('Edit profile'));
      await qa.type(find.byType(TextField).first, 'Luna Belle');
      await qa.tap(find.text('Save changes'));
      await qa.see('Luna Belle was updated.');
      qa.event('pet.update.completed');
      await qa.gone('Luna Belle was updated.', seconds: 8);
    });

    await qa.step('Edge: dismissing the time picker keeps the time', () async {
      await qa.tap(find.text('Apoquel'));
      await qa.see('Morning reminder');
      await qa.see('8:00 AM');
      await qa.tap(find.text('Morning reminder'));
      await qa.tap(find.text('Cancel'));
      qa.event('medication.time_pick_cancelled', {'part': 'morning'});
      qa.noEvent('medication.times.completed');
      expect(_apoquel(_care(t)).times, isEmpty);
    });

    await qa.step(
      'Custom reminder time: 7:15 AM saved, shown everywhere',
      () async {
        await qa.tap(find.text('Morning reminder'));
        await qa.tap(find.byIcon(Icons.keyboard_outlined));
        final fields = find.descendant(
          of: find.byType(Dialog),
          matching: find.byType(TextField),
        );
        await qa.type(fields.at(0), '7');
        await qa.type(fields.at(1), '15');
        await qa.tap(find.text('OK'));
        await qa.see('Morning reminder set to 7:15 AM.');
        qa.event('medication.times.completed', {'customTimes': 1});
        expect(_apoquel(_care(t)).times, {DayPart.morning: 7 * 60 + 15});
        // Survives a cold reload (SQLite v2 column).
        final reloaded = CareRepository(store: HouseholdStore());
        await reloaded.restore();
        expect(_apoquel(reloaded).times, {DayPart.morning: 7 * 60 + 15});
        await qa.tap(find.byTooltip('Back'));
        await qa.tapLabel('Today');
        await qa.see('7:15 AM', partial: true);
        await qa.tapLabel('Pets');
      },
    );

    await qa.step('Pro gate: second pet opens paywall', () async {
      await qa.tap(find.byTooltip('Add pet'));
      await qa.see('Room for every pet');
      await qa.tap(find.byTooltip('Close'));
      expect(_care(t).pets, hasLength(1));
    });

    await qa.step('Pro gate: household invite opens paywall', () async {
      await qa.tapLabel('Household');
      await qa.tap(find.text('Invite someone'));
      qa.event('billing.paywall.opened', {'reason': 'invite'});
      await qa.tap(find.byTooltip('Close'));
      qa.event('billing.paywall.dismissed', {'reason': 'invite'});
    });

    await qa.step('Reports show accurate free history', () async {
      await qa.tapLabel('Reports');
      await qa.see(
        'Pro makes a PDF of the last 90 days your vet can read, with who gave each dose.',
      );
      final care = _care(t);
      final report = care.reportFor(care.pets.single.id, 30);
      expect(report.lines.fold<int>(0, (sum, l) => sum + l.given), 1);
      expect(report.skipped, 0);
    });

    // v14 Reports has no range picker: the Pro gate is the vet export
    // (a PDF of the last 90 days), and Free still sees its own 28 days.
    await qa.step('Pro gate: vet export opens paywall', () async {
      await qa.tap(find.text('Share report with vet'));
      await qa.see('Walk into the vet with answers');
      qa.event('billing.paywall.opened', {'reason': 'vet_export'});
      await qa.tap(find.byTooltip('Close'));
      expect(_care(t).historyFromDay, isNotNull);
    });

    await qa.step('Offline data survives a cold reload', () async {
      final reloaded = CareRepository(store: HouseholdStore());
      await reloaded.restore();
      expect(reloaded.pets.single.name, 'Luna Belle');
      expect(reloaded.medications.map((m) => m.name), ['Apoquel']);
      expect(reloaded.medications.single.dosesLeft, 3);
    });

    await qa.step('Stop medicine and its SnackBar dismisses', () async {
      await qa.tapLabel('Pets');
      await qa.tap(find.text('Apoquel'));
      await qa.tap(find.text('Stop medicine'));
      await qa.tap(find.text('Stop medicine').last);
      await qa.see('Apoquel was stopped.');
      qa.event('medication.remove.completed');
      await qa.gone('Apoquel was stopped.', seconds: 8);
    });

    await qa.step(
      'Edge: a stopped medicine frees a slot under the cap',
      () async {
        final care = _care(t);
        expect(care.canAddMedication(care.pets.single.id), isTrue);
      },
    );

    await qa.step('Settings: restore purchases without a store', () async {
      // v14: the settings gear sits in the Household tab's header.
      await qa.tapLabel('Household');
      await qa.tap(find.byTooltip('Settings'));
      await qa.tap(find.text('Restore purchases'));
      qa.event('billing.restore.requested');
    });

    await qa.step('Pro gate: weekly summary opens paywall', () async {
      await qa.see('Weekly summary');
      // The See Pro on the Weekly summary row, not the plan card's.
      await qa.tap(
        find.descendant(
          of: find.widgetWithText(ListTile, 'Weekly summary'),
          matching: find.text('See Pro'),
        ),
      );
      await qa.see('Know the week went right');
      qa.event('billing.paywall.opened', {'reason': 'weekly_summary'});
      await qa.tap(find.byTooltip('Close'));
    });

    await qa.step('Settings: delete account wipes the phone', () async {
      await qa.tap(find.text('Delete account on this phone'));
      await qa.tap(find.text('Delete'));
      await qa.see('Get started');
      qa.event('account.deleted');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('household_v2'), isNull);
    });

    qa.finish();
  });

  testWidgets('pro + backend: shared household between two phones', (t) async {
    final qa = _qa(t);
    await _launchFresh(qa);
    final partner = HouseholdApi(Uri.parse(AppConfig.apiBaseUrl));
    late HouseholdSession session;

    await qa.step('Onboard and start the Pro trial', () async {
      await qa.tap(find.text('Get started'));
      await qa.type(find.byType(TextFormField), 'Miso');
      await qa.tap(find.text('Cat'));
      await qa.tap(find.text('Continue'));
      await qa.tap(find.text('Skip'));
      await qa.tap(find.text('Continue'));
      await qa.tap(find.text('Not now'));
      await qa.tap(find.text('Go to Today'));
      await qa.tap(find.text('Continue free with 1 pet'));
      // Pro only comes from RevenueCat; stand in for its entitlement listener.
      _care(t).applyStoreEntitlement(true, BillingPlan.yearly);
      await qa.settle(500);
      qa.event('billing.store.entitlement_changed');
      expect(_care(t).isPro, isTrue);
    });

    await qa.step('Add Insulin with 4 doses tracked', () async {
      await qa.tap(find.text('Add first medicine'));
      await qa.addMedicine('Insulin', supply: 4);
      qa.event('medication.add.completed');
    });

    await qa.step('Backend: invite creates the household online', () async {
      await qa.tapLabel('Household');
      await qa.tap(find.text('Invite someone'));
      // The code is fetched as the flow opens (step 1: who it's for).
      await qa.see('Who are you inviting?');
      await qa.waitUntil(
        () => _care(t).inviteCode.isNotEmpty,
        seconds: 15,
        what: 'invite code from server',
      );
      expect(_care(t).isConnected, isTrue);
      expect(_care(t).isPro, isTrue, reason: 'trial must survive going online');
      // The code shows as soon as the server answers; household.connected is
      // logged after the follow-up steps (store identity, outbox, photos).
      // Push registration never delays it (it runs in the background).
      await qa.waitUntil(
        () => qa.count('household.connected') > 0,
        seconds: 20,
        what: 'household.connected',
      );
      qa.event('household.connected');
      await qa.tap(find.byTooltip('Close'));
    });

    await qa.step('Backend: partner joins with the invite code', () async {
      session = await partner.join(code: _care(t).inviteCode, name: 'Sara');
      partner.token = session.token;
      expect(session.snapshot.pets.map((p) => p.name), ['Miso']);
      expect(session.snapshot.medications.map((m) => m.name), ['Insulin']);
    });

    await qa.step('Backend: rejects a bad token and a wrong code', () async {
      final stranger = HouseholdApi(Uri.parse(AppConfig.apiBaseUrl))
        ..token = 'not-a-real-token';
      await expectLater(
        stranger.fetchHousehold(),
        throwsA(
          isA<HouseholdException>().having(
            (e) => e.kind,
            'kind',
            HouseholdErrorKind.unauthorized,
          ),
        ),
      );
      await expectLater(
        HouseholdApi(Uri.parse(AppConfig.apiBaseUrl))
            .join(code: 'ZZZZZZ', name: 'Eve'),
        throwsA(isA<HouseholdException>()),
      );
    }, independent: true);

    DoseRecord partnerDose([LogOutcome outcome = LogOutcome.given]) =>
        DoseRecord(
          id: newId('log'),
          medicationId: session.snapshot.medications.single.id,
          part: DayPart.morning,
          day: dayKey(DateTime.now()),
          memberId: session.snapshot.memberId,
          outcome: outcome,
          amount: '',
          timeLabel: '9:00 AM',
        );

    await qa.step(
      'Backend: "not sure" then given resolves the check',
      () async {
        await partner.logDose(partnerDose(LogOutcome.uncertain));
        final saved = await partner.logDose(partnerDose());
        expect(saved.log.outcome, LogOutcome.given);
      },
    );

    await qa.step(
      'Backend: logging the same dose twice is a conflict',
      () async {
        await expectLater(
          partner.logDose(partnerDose()),
          throwsA(
            isA<HouseholdException>().having(
              (e) => e.kind,
              'kind',
              HouseholdErrorKind.conflict,
            ),
          ),
        );
      },
    );

    await qa.step('Sync: pull to refresh shows the partner dose', () async {
      await qa.tapLabel('Today');
      final before = qa.count('household.synced');
      await qa.pullToRefresh();
      await qa.waitUntil(
        () => qa.count('household.synced') > before,
        seconds: 15,
        what: 'household.synced after pull to refresh',
      );
      await qa.see('Everyone is covered for today');
      qa.event('push.partner_detected');
    });

    await qa.step('Safety across phones: guard names the partner', () async {
      await qa.tap(find.text('Insulin'));
      await qa.see('Sara', partial: true);
      await qa.tap(find.text('Don’t give it'));
    });

    await qa.step('Pro: low-supply banner, refill syncs to backend', () async {
      expect(_care(t).medications.single.dosesLeft, 3);
      await qa.tap(find.text('Refill'));
      await qa.see('Supply · low');
      await qa.tap(find.text('I refilled it'));
      await qa.see('The box is full again.');
      qa.event('medication.refill.completed');
      await qa.waitUntil(
        () async =>
            (await partner.fetchHousehold()).medications.single.dosesLeft == 4,
        seconds: 15,
        what: 'partner sees refilled supply',
      );
      // Refill opens from the medication page; back out until the tabs show
      // (bottom tabs on phones, a side rail on tablets).
      final petsTab = find.byWidgetPredicate(
        (w) =>
            w is Semantics &&
            w.properties.button == true &&
            w.properties.label == 'Pets',
      );
      bool tabsShown() =>
          petsTab.evaluate().isNotEmpty ||
          find.byType(NavigationRail).evaluate().isNotEmpty &&
              find.byTooltip('Back').evaluate().isEmpty;
      for (
        var i = 0;
        i < 3 && !tabsShown() && find.byTooltip('Back').evaluate().isNotEmpty;
        i++
      ) {
        await qa.tap(find.byTooltip('Back').last);
      }
    });

    await qa.step('Pro: second pet allowed and synced', () async {
      await qa.tapLabel('Pets');
      await qa.tap(find.byTooltip('Add pet'));
      await qa.type(find.widgetWithText(TextField, 'Pet name'), 'Pepper');
      await qa.tap(find.text('Dog'));
      await qa.tap(find.text('Save pet'));
      qa.event('pet.add.completed');
      await qa.waitUntil(
        () async => (await partner.fetchHousehold()).pets.length == 2,
        seconds: 15,
        what: 'partner sees second pet',
      );
    });

    await qa.step('Pro: vet report sharing is unlocked', () async {
      await qa.tapLabel('Reports');
      await qa.see('Share report with vet');
      qa.absent(
        'Pro makes a PDF of the last 90 days your vet can read, with who gave each dose.',
      );
    });

    await qa.step('Leave household resets this phone only', () async {
      // v14: the settings gear sits in the Household tab's header.
      await qa.tapLabel('Household');
      await qa.tap(find.byTooltip('Settings'));
      await qa.tap(find.text('Leave household'));
      await qa.tap(find.text('Leave'));
      // Reset finishes after the store sign-out and local clears.
      await qa.waitUntil(
        () => qa.count('household.reset') > 0,
        seconds: 20,
        what: 'household.reset',
      );
      qa.event('household.reset');
      expect(
        (await partner.fetchHousehold()).pets,
        hasLength(2),
        reason: 'partner keeps the shared household',
      );
    });

    qa.finish();
  });
}

Qa _qa(WidgetTester t) => Qa(
  t,
  hasEvent: (name, fields) => AppLog.testRecords.any(
    (r) =>
        r.name == name &&
        fields.entries.every((e) => r.fields[e.key] == e.value),
  ),
  eventCount: AppLog.logCount,
);

/// A true first launch: since the move to SQLite and the Keychain, clearing
/// preferences alone leaves the last run’s household behind (e.g. after an
/// interrupted run), so the database file and secure tokens go too.
Future<void> _launchFresh(Qa qa) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.clear();
  await LocalDatabase.shared.deleteFile();
  await SecureTokens.deleteAll();
  AppLog.enableTestCapture();
  await qa.t.pumpWidget(await bootstrap());
  await qa.settle(1500);
}

Medication _apoquel(CareRepository care) =>
    care.medications.singleWhere((m) => m.name == 'Apoquel');

CareRepository _care(WidgetTester t) => Provider.of<CareRepository>(
  t.element(find.byType(Scaffold).first),
  listen: false,
);
