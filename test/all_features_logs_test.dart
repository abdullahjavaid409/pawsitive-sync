import 'package:flutter_test/flutter_test.dart';
import 'package:pawsitive_sync/core/constants/pet_limits.dart';
import 'package:pawsitive_sync/core/legal/app_links.dart';
import 'package:pawsitive_sync/core/logging/app_log.dart';
import 'package:pawsitive_sync/data/care_repository.dart';
import 'package:pawsitive_sync/data/household_api.dart';
import 'package:pawsitive_sync/data/household_store.dart';
import 'package:pawsitive_sync/data/push_service.dart';
import 'package:pawsitive_sync/domain/models.dart';
import 'package:pawsitive_sync/ui/onboarding/onboarding_view_model.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_household_api.dart';
import 'test_log_helpers.dart';

/// Every repository feature: happy path, edge case, and structured log.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppLog.enableTestCapture();
  });

  tearDown(AppLog.disableTestCapture);

  Future<CareRepository> freshCare() async {
    final care = CareRepository(clock: () => DateTime(2026, 10, 3, 14));
    await care.addPet(name: 'Milo', species: Species.cat);
    return care;
  }

  group('Pets', () {
    test('add offline logs pet.add.completed', () async {
      await freshCare();
      expectLogged('pet.add.completed', fields: {'offline': true});
    });

    test('add rejected empty name logs pet.add_rejected', () async {
      final care = CareRepository.sample();
      expect(await care.addPet(name: '  ', species: Species.cat), isNull);
      expectLogged('pet.add_rejected', fields: {'reason': 'missing_name'});
    });

    test('add blocked on free tier logs pet.add.blocked', () async {
      final care = await freshCare();
      expect(await care.addPet(name: 'Juniper', species: Species.dog), isNull);
      expectLogged('pet.add.blocked', fields: {'reason': 'free_tier'});
    });

    test('add blocked at household cap logs household_limit', () async {
      final care = CareRepository.sample();
      care.applyStoreEntitlement(true, BillingPlan.yearly);
      for (var i = care.pets.length; i < PetLimits.maxPetsPerHousehold; i++) {
        await care.addPet(name: 'Pet $i', species: Species.cat);
      }
      expect(await care.addPet(name: 'Overflow', species: Species.dog), isNull);
      expectLogged('pet.add.blocked', fields: {'reason': 'household_limit'});
    });

    test('update success logs pet.update.completed', () async {
      final care = await freshCare();
      final petId = care.pets.first.id;
      expect(
        await care.updatePet(
          petId: petId,
          name: 'Milo Jr',
          species: Species.cat,
          ageYears: 5,
        ),
        isTrue,
      );
      expectLogged('pet.update.completed');
    });

    test('update missing pet logs pet.update.missing', () async {
      final care = CareRepository.sample();
      expect(
        await care.updatePet(
          petId: 'ghost',
          name: 'Ghost',
          species: Species.cat,
        ),
        isFalse,
      );
      expectLogged('pet.update.missing', fields: {'petId': 'ghost'});
    });

    test('update noop logs pet.update.noop', () async {
      final care = CareRepository.sample();
      final pet = care.primaryPet!;
      expect(
        await care.updatePet(
          petId: pet.id,
          name: pet.name,
          species: pet.species,
          ageYears: pet.ageYears,
          weightKg: pet.weightKg,
          conditions: pet.conditions,
        ),
        isTrue,
      );
      expectLogged('pet.update.noop', fields: {'petId': pet.id});
    });
  });

  group('Medications', () {
    test('add success logs medication.add.completed', () async {
      final care = await freshCare();
      expect(
        await care.addMedication(
          petId: care.pets.first.id,
          name: 'Insulin',
          amount: '2 units',
          parts: [DayPart.morning],
          supplyTotal: 30,
        ),
        isTrue,
      );
      expectLogged('medication.add.completed', fields: {'tracksSupply': true});
    });

    test('add rejected missing name logs medication.add_rejected', () async {
      final care = CareRepository.sample();
      expect(
        await care.addMedication(
          petId: 'miso',
          name: ' ',
          amount: '1 tab',
          parts: [DayPart.morning],
        ),
        isFalse,
      );
      expectLogged('medication.add_rejected', fields: {'reason': 'missing_name'});
    });

    test('add rejected empty schedule logs missing_parts', () async {
      final care = CareRepository.sample();
      expect(
        await care.addMedication(
          petId: 'miso',
          name: 'Test',
          amount: '1 tab',
          parts: [],
        ),
        isFalse,
      );
      expectLogged('medication.add_rejected', fields: {'reason': 'missing_parts'});
    });

    test('add rejected missing pet logs missing_pet', () async {
      final care = CareRepository.sample();
      expect(
        await care.addMedication(
          petId: 'missing',
          name: 'Test',
          amount: '1 tab',
          parts: [DayPart.morning],
        ),
        isFalse,
      );
      expectLogged('medication.add_rejected', fields: {'reason': 'missing_pet'});
    });

    test('refill logs medication.refill.completed', () async {
      final care = CareRepository.sample();
      final med = care.medications.firstWhere((m) => m.tracksSupply);
      expect(await care.refill(med.id), isTrue);
      expectLogged('medication.refill.completed');
    });

    test('remove logs medication.remove.completed', () async {
      final care = CareRepository.sample();
      final med = care.medications.first;
      expect(await care.removeMedication(med.id), isTrue);
      expectLogged('medication.remove.completed');
    });
  });

  group('Doses', () {
    test('log success logs dose.log.completed', () async {
      final care = CareRepository.sample(
        clock: () => DateTime(2026, 10, 3, 14),
      );
      final dose = care.doses.firstWhere((d) => d.status == DoseStatus.due);
      expect(
        await care.logDose(
          doseId: dose.id,
          memberId: 'you',
          amount: dose.amount,
          timeLabel: '2:00 PM',
        ),
        isTrue,
      );
      expectLogged('dose.log.completed', fields: {'doseId': dose.id});
    });

    test('double log rejected logs dose.log.rejected', () async {
      final care = CareRepository.sample(
        clock: () => DateTime(2026, 10, 3, 14),
      );
      final dose = care.doses.firstWhere((d) => d.status == DoseStatus.due);
      await care.logDose(
        doseId: dose.id,
        memberId: 'you',
        amount: dose.amount,
        timeLabel: '2:00 PM',
      );
      expect(
        await care.logDose(
          doseId: dose.id,
          memberId: 'you',
          amount: dose.amount,
          timeLabel: '2:05 PM',
        ),
        isFalse,
      );
      expectLogged('dose.log.rejected', fields: {'reason': 'already_logged'});
    });

    test('uncertain logs dose.uncertain.completed', () async {
      final care = CareRepository.sample(
        clock: () => DateTime(2026, 10, 3, 14),
      );
      final dose = care.doses.firstWhere((d) => d.status == DoseStatus.due);
      expect(await care.markDoseUncertain(dose.id), isTrue);
      expectLogged('dose.uncertain.completed');
    });

    test('skip logs dose.skip.completed', () async {
      final care = CareRepository.sample(
        clock: () => DateTime(2026, 10, 3, 14),
      );
      final dose = care.doses.firstWhere((d) => d.status == DoseStatus.due);
      expect(await care.skipDose(dose.id), isTrue);
      expectLogged('dose.skip.completed');
    });

    test('uncertain dose can be resolved as skipped', () async {
      final care = CareRepository.sample(
        clock: () => DateTime(2026, 10, 3, 14),
      );
      final dose = care.doses.firstWhere((d) => d.status == DoseStatus.due);
      await care.markDoseUncertain(dose.id);
      expect(await care.skipDose(dose.id), isTrue);
      expectLogged('dose.skip.completed');
      expectNotLogged('dose.skip.rejected');
    });

    test('log on removed medication logs dose.log.rejected', () async {
      final care = CareRepository.sample(
        clock: () => DateTime(2026, 10, 3, 14),
      );
      final dose = care.doses.firstWhere((d) => d.status == DoseStatus.due);
      final medId = dose.id.substring(0, dose.id.lastIndexOf('.'));
      await care.removeMedication(medId);
      expect(
        await care.logDose(
          doseId: dose.id,
          memberId: 'you',
          amount: dose.amount,
          timeLabel: '2:00 PM',
        ),
        isFalse,
      );
      expectLogged('dose.log.rejected', fields: {'reason': 'missing_medication'});
    });
  });

  group('Care events', () {
    test('add logs care_event.added', () async {
      final care = CareRepository.sample();
      expect(
        await care.addCareEvent(
          petId: 'miso',
          title: 'Rabies booster',
          kind: CareEventKind.vaccine,
          dueDate: care.now.add(const Duration(days: 14)),
        ),
        isTrue,
      );
      expectLogged('care_event.added', fields: {'kind': 'vaccine'});
    });

    test('rejected missing pet logs care_event.rejected', () async {
      final care = CareRepository.sample();
      expect(
        await care.addCareEvent(
          petId: 'missing',
          title: 'Vet',
          kind: CareEventKind.vetVisit,
          dueDate: care.now,
        ),
        isFalse,
      );
      expectLogged('care_event.rejected', fields: {'reason': 'missing_pet'});
    });

    test('rejected empty title logs care_event.rejected', () async {
      final care = CareRepository.sample();
      expect(
        await care.addCareEvent(
          petId: 'miso',
          title: '  ',
          kind: CareEventKind.vetVisit,
          dueDate: care.now,
        ),
        isFalse,
      );
      expectLogged('care_event.rejected', fields: {'reason': 'missing_title'});
    });

    test('remove logs care_event.removed', () async {
      final care = CareRepository.sample();
      await care.addCareEvent(
        petId: 'miso',
        title: 'Checkup',
        kind: CareEventKind.vetVisit,
        dueDate: care.now.add(const Duration(days: 3)),
      );
      await care.removeCareEvent(care.careEvents.single.id);
      expectLogged('care_event.removed');
    });
  });

  group('Pro / Free — isPro unlocks all paid gates', () {
    test('free: all Pro gates false, safety features work', () async {
      final care = await freshCare();
      expect(care.isPro, isFalse);
      expect(care.canInviteHousehold, isFalse);
      expect(care.canShareVetReport, isFalse);
      expect(care.canShowLowSupplyAlerts, isFalse);
      expect(care.canAddPet, isFalse);
    });

    test('RevenueCat entitlement unlocks all gates', () async {
      final care = await freshCare();
      care.applyStoreEntitlement(true, BillingPlan.yearly);
      expect(care.isPro, isTrue);
      expect(care.canInviteHousehold, isTrue);
      expect(care.canShareVetReport, isTrue);
      expect(care.canShowLowSupplyAlerts, isTrue);
      expect(care.canAddPet, isTrue);
      expectLogged('billing.store.entitlement_changed', fields: {'active': true});
    });

    test('trial started before sharing survives going online', () async {
      final adapter = FakeHouseholdAdapter([
        (201, connectHouseholdBody(isPro: false)),
        (200, {'isPro': true, 'plan': 'yearly'}), // trial pushed online
        (200, {'ok': true}), // push device register
      ]);
      final care = CareRepository(
        api: fakeHouseholdApi(adapter),
        clock: () => DateTime(2026, 10, 3, 14),
      );
      await care.addPet(name: 'Milo', species: Species.cat);
      care.applyStoreEntitlement(true, BillingPlan.yearly);
      expect(await care.connect(), isNull);
      expect(care.isPro, isTrue);
      expectLogged('billing.pro.carried_online');
    });

    test('paying subscriber keeps Pro when the server lags behind', () async {
      // Webhook not processed yet: server still says Free on every refresh.
      final care = CareRepository(
        api: fakeHouseholdApi(FakeHouseholdAdapter([
          (201, connectHouseholdBody(isPro: false)),
          (200, {'ok': true}), // push device register
          (200, connectHouseholdBody(isPro: false)), // sync refresh
        ])),
        clock: () => DateTime(2026, 10, 3, 14),
      );
      await care.addPet(name: 'Milo', species: Species.cat);
      await care.connect();
      expect(care.isPro, isFalse);
      care.debugStorePro = true; // App Store says this phone paid
      await care.sync();
      expect(care.isPro, isTrue);
      expect(care.canInviteHousehold, isTrue);
      expect(care.canAddPet, isTrue);
    });

    test('partner gets Pro from the server without their own subscription', () async {
      final care = CareRepository(
        api: fakeHouseholdApi(FakeHouseholdAdapter([
          (201, connectHouseholdBody(isPro: true)),
          (200, {'ok': true}),
        ])),
        clock: () => DateTime(2026, 10, 3, 14),
      );
      await care.addPet(name: 'Milo', species: Species.cat);
      await care.connect();
      care.debugStorePro = false;
      expect(care.isPro, isTrue);
    });

    test('live store update: purchase lands late, then expires (solo)', () async {
      final care = CareRepository(clock: () => DateTime(2026, 10, 3, 14));
      await care.addPet(name: 'Milo', species: Species.cat);
      expect(care.isPro, isFalse);
      care.applyStoreEntitlement(true, BillingPlan.yearly);
      expect(care.isPro, isTrue);
      expectLogged(
        'billing.store.entitlement_changed',
        fields: {'active': true},
      );
      care.applyStoreEntitlement(false, null);
      expect(care.isPro, isFalse, reason: 'own subscription ended');
      expect(care.canAddPet, isFalse);
    });

    test('store expiry keeps household Pro a partner pays for', () async {
      final care = CareRepository(
        api: fakeHouseholdApi(FakeHouseholdAdapter([
          (201, connectHouseholdBody(isPro: true)),
          (200, {'ok': true}),
        ])),
        clock: () => DateTime(2026, 10, 3, 14),
      );
      await care.addPet(name: 'Milo', species: Species.cat);
      await care.connect();
      care.applyStoreEntitlement(true, BillingPlan.monthly);
      care.applyStoreEntitlement(false, null);
      expect(care.isPro, isTrue, reason: 'server still says household is Pro');
    });

    // RevenueCat's SDK caches the subscription for offline launches; the app
    // never keeps its own copy, so a solo phone can't be Pro without it.
    test('solo Pro is never restored from local storage', () async {
      final care = CareRepository(
        store: HouseholdStore(),
        clock: () => DateTime(2026, 10, 3, 14),
      );
      await care.addPet(name: 'Milo', species: Species.cat);
      care.applyStoreEntitlement(true, BillingPlan.yearly);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final reloaded = CareRepository(store: HouseholdStore());
      await reloaded.restore();
      expect(reloaded.isPro, isFalse);
      expect(reloaded.pets.single.name, 'Milo');
    });

    test('store account id is per household, never the shared "you"', () async {
      final care = CareRepository(
        api: fakeHouseholdApi(FakeHouseholdAdapter([
          (201, connectHouseholdBody(householdId: 'hh_42')),
          (200, {'ok': true}), // push device register
        ])),
        clock: () => DateTime(2026, 10, 3, 14),
      );
      await care.addPet(name: 'Milo', species: Species.cat);
      expect(care.billingUserId, isEmpty, reason: 'offline stays anonymous');
      await care.connect();
      expect(care.billingUserId, 'hh_42:you');
    });

    test('shared household id survives a restart', () async {
      final care = CareRepository(
        api: fakeHouseholdApi(FakeHouseholdAdapter([
          (201, connectHouseholdBody(householdId: 'hh_42')),
          (200, {'ok': true}),
        ])),
        store: HouseholdStore(),
        clock: () => DateTime(2026, 10, 3, 14),
      );
      await care.addPet(name: 'Milo', species: Species.cat);
      await care.connect();
      final reloaded = CareRepository(
        api: HouseholdApi(Uri.parse('https://example.test')),
        store: HouseholdStore(),
      );
      await reloaded.restore();
      expect(reloaded.billingUserId, 'hh_42:you');
    });

    test('reset revokes Pro and logs household.reset', () async {
      final care = await freshCare();
      care.applyStoreEntitlement(true, BillingPlan.yearly);
      await care.reset();
      expect(care.isPro, isFalse);
      expect(care.canInviteHousehold, isFalse);
      expectLogged('household.reset');
    });

    test('setPlan logs billing.plan.changed', () async {
      final care = CareRepository.sample();
      await care.setPlan(BillingPlan.monthly);
      expectLogged('billing.plan.changed', fields: {'plan': 'monthly'});
    });

    test('restore without RevenueCat logs billing.restore.skipped', () async {
      final care = CareRepository.sample();
      expect(await care.restoreBilling(), isFalse);
      expectLogged('billing.restore.requested');
      expectLogged('billing.restore.skipped', fields: {'reason': 'not_configured'});
    });
  });

  group('Household & sync', () {
    test('join short code logs household.join_rejected', () async {
      final care = CareRepository.sample();
      expect(await care.join(code: 'ABC', name: 'Alex'), isNotNull);
      expectLogged('household.join_rejected', fields: {'reason': 'short_code'});
    });

    test('join empty name logs household.join_rejected', () async {
      final care = CareRepository(
        api: HouseholdApi(Uri.parse('https://example.test')),
      );
      expect(await care.join(code: 'ABCDEF', name: '  '), isNotNull);
      expectLogged('household.join_rejected', fields: {'reason': 'missing_name'});
    });

    test('join without API logs household.join_skipped', () async {
      final care = CareRepository.sample();
      expect(await care.join(code: 'ABCDEF', name: 'Alex'), isNotNull);
      expectLogged('household.join_skipped', fields: {'reason': 'no_api'});
    });

    test('connect without API logs household.connect_skipped', () async {
      final care = CareRepository.sample();
      expect(await care.connect(), isNotNull);
      expectLogged('household.connect_skipped', fields: {'reason': 'no_api'});
    });

    test('sync offline logs household.sync_skipped', () async {
      final care = CareRepository.sample();
      await care.sync();
      expectLogged('household.sync_skipped', fields: {'reason': 'no_api'});
    });

    test('sync not connected logs not_connected', () async {
      final care = CareRepository(
        api: HouseholdApi(Uri.parse('https://example.test')),
        clock: () => DateTime(2026, 10, 3, 14),
      );
      await care.sync();
      expectLogged('household.sync_skipped', fields: {'reason': 'not_connected'});
    });
  });

  group('Sitter browser link', () {
    test('free tier skips with sitter.link_skipped', () async {
      final care = await freshCare();
      expect(await care.ensureSitterWebLink(), isNull);
      expectLogged('sitter.link_skipped', fields: {'reason': 'free_tier'});
    });

    test('not connected skips with sitter.link_skipped', () async {
      final care = CareRepository(
        api: HouseholdApi(Uri.parse('https://example.test')),
        clock: () => DateTime(2026, 10, 3, 14),
      );
      await care.addPet(name: 'Milo', species: Species.cat);
      care.applyStoreEntitlement(true, BillingPlan.yearly);
      expect(await care.ensureSitterWebLink(), isNull);
      expectLogged('sitter.link_skipped', fields: {'reason': 'not_connected'});
    });

    test('creates link and logs sitter.link_created', () async {
      final adapter = FakeHouseholdAdapter([
        (201, connectHouseholdBody()),
        (200, {'ok': true}), // push device register
        (
          201,
          {
            'token': 'sitter-secret-token',
            'expiresAt': '2026-11-03T00:00:00.000Z',
            'url': '/sitter#t=sitter-secret-token',
          },
        ),
      ]);
      final api = fakeHouseholdApi(adapter);
      final care = CareRepository(
        api: api,
        clock: () => DateTime(2026, 10, 3, 14),
      );
      await care.addPet(name: 'Milo', species: Species.cat);
      care.applyStoreEntitlement(true, BillingPlan.yearly);
      expect(await care.connect(), isNull);
      AppLog.testRecords.clear();

      final link = await care.ensureSitterWebLink();
      expect(link, contains('sitter-secret-token'));
      expectLogged('sitter.link_created');
    });

    test('cached token logs sitter.link_cached', () async {
      SharedPreferences.setMockInitialValues({
        'sitter_web_token_v1:ABC234': 'cached-sitter-token',
      });
      final connected = CareRepository(
        api: fakeHouseholdApi(FakeHouseholdAdapter([
          (201, connectHouseholdBody(inviteCode: 'ABC234')),
          (200, {'ok': true}), // push device register
        ])),
        clock: () => DateTime(2026, 10, 3, 14),
      );
      await connected.addPet(name: 'Milo', species: Species.cat);
      connected.applyStoreEntitlement(true, BillingPlan.yearly);
      await connected.connect();
      AppLog.testRecords.clear();

      final link = await connected.ensureSitterWebLink();
      expect(link, contains('cached-sitter-token'));
      expectLogged('sitter.link_cached');
      expectNotLogged('sitter.link_created');
    });

    test('API failure logs sitter.link_failed', () async {
      final adapter = FakeHouseholdAdapter([
        (201, connectHouseholdBody()),
        (200, {'ok': true}), // push device register
        (403, {'error': 'Browser sitter links need Pawsitive Pro.'}),
      ]);
      final care = CareRepository(
        api: fakeHouseholdApi(adapter),
        clock: () => DateTime(2026, 10, 3, 14),
      );
      await care.addPet(name: 'Milo', species: Species.cat);
      care.applyStoreEntitlement(true, BillingPlan.yearly);
      await care.connect();
      AppLog.testRecords.clear();

      expect(await care.ensureSitterWebLink(), isNull);
      expectLogged('sitter.link_failed');
    });
  });

  group('Partner push on sync', () {
    test('sync detects partner dose and logs push.partner_detected', () async {
      final adapter = FakeHouseholdAdapter([
        (201, connectHouseholdBody()),
        (200, {'ok': true}), // push device register
        (
          200,
          connectHouseholdBody(
            logs: [
              {
                'id': 'log-dan-1',
                'medicationId': 'insulin',
                'part': 'morning',
                'day': '2026-10-03',
                'memberId': 'dan',
                'outcome': 'given',
                'amount': '2 u',
                'timeLabel': '8:05 AM',
              },
            ],
          ),
        ),
      ]);
      final care = CareRepository(
        api: fakeHouseholdApi(adapter),
        clock: () => DateTime(2026, 10, 3, 14),
      );
      await care.addPet(name: 'Miso', species: Species.cat);
      care.applyStoreEntitlement(true, BillingPlan.yearly);
      await care.connect();
      AppLog.testRecords.clear();

      await care.sync(force: true);
      expectLogged('household.synced');
      expectLogged('push.partner_detected', fields: {'logId': 'log-dan-1'});
    });

    test('own dose on sync does not log push.partner_detected', () async {
      final adapter = FakeHouseholdAdapter([
        (201, connectHouseholdBody()),
        (200, {'ok': true}), // push device register
        (
          200,
          connectHouseholdBody(
            logs: [
              {
                'id': 'log-you-1',
                'medicationId': 'insulin',
                'part': 'morning',
                'day': '2026-10-03',
                'memberId': 'you',
                'outcome': 'given',
                'amount': '2 u',
                'timeLabel': '8:05 AM',
              },
            ],
          ),
        ),
      ]);
      final care = CareRepository(
        api: fakeHouseholdApi(adapter),
        clock: () => DateTime(2026, 10, 3, 14),
      );
      await care.addPet(name: 'Miso', species: Species.cat);
      care.applyStoreEntitlement(true, BillingPlan.yearly);
      await care.connect();
      AppLog.testRecords.clear();

      await care.sync(force: true);
      expectLogged('household.synced');
      expectNotLogged('push.partner_detected');
    });
  });

  group('Push service null safety', () {
    test('register skipped without API logs push.register_skipped', () async {
      await PushService.registerIfConnected(null);
      expectLogged('push.register_skipped', fields: {'reason': 'no_api'});
    });

    test('register skipped without token logs not_connected', () async {
      await PushService.registerIfConnected(
        HouseholdApi(Uri.parse('https://example.test')),
      );
      expectLogged('push.register_skipped', fields: {'reason': 'not_connected'});
    });

    test('partner notify skipped when disabled logs push.partner_skipped', () async {
      SharedPreferences.setMockInitialValues({'push_household_enabled': false});
      await PushService.notifyPartnerLogged(
        logId: 'log1',
        who: 'Dan',
        medicationName: 'Insulin',
        petName: 'Miso',
      );
      expectLogged('push.partner_skipped', fields: {'reason': 'disabled'});
    });

    test('partner notify skipped for empty log id', () async {
      await PushService.notifyPartnerLogged(
        logId: '',
        who: 'Dan',
        medicationName: 'Insulin',
        petName: 'Miso',
      );
      expectLogged('push.partner_skipped', fields: {'reason': 'empty_log_id'});
    });

    test('preference toggle logs push.preference', () async {
      await PushService.setHouseholdPushEnabled(false);
      expectLogged('push.preference', fields: {'enabled': false});
    });
  });

  group('App links', () {
    test('sitterWebLink encodes token safely', () {
      final link = AppLinks.sitterWebLink('abc+def/token');
      expect(link, endsWith('/sitter#t=abc%2Bdef%2Ftoken'));
      expect(link, isNot(contains('?t=')), reason: 'token must stay out of server logs');
    });

    test('no invite link until the App Store ID is set (never a dead URL)', () {
      expect(AppLinks.householdJoinLink('ABC123'), isNull);
    });

    test('legal links point at live pages, support is a real inbox', () {
      expect(AppLinks.privacy, 'https://sites.google.com/view/pawasitive/home');
      expect(AppLinks.terms, contains('apple.com/legal'));
      expect(AppLinks.support, 'mailto:workplace0331@gmail.com');
      for (final link in [AppLinks.privacy, AppLinks.terms, AppLinks.support]) {
        expect(link, isNot(contains('pawsitivesync.app')));
      }
    });
  });

  group('Onboarding & reports', () {
    test('applyOnboarding logs household.created_from_onboarding', () {
      final care = CareRepository(clock: () => DateTime(2026, 10, 3, 14));
      final model = OnboardingViewModel()
        ..setName('Buddy')
        ..setSpecies(Species.dog)
        ..changeAge(4)
        ..toggleCondition('Arthritis');
      care.applyOnboarding(model);
      expect(care.primaryPet!.name, 'Buddy');
      expectLogged('household.created_from_onboarding');
    });

    test('reportFor works on free tier (view only)', () async {
      final care = await freshCare();
      await care.addMedication(
        petId: care.pets.first.id,
        name: 'Daily',
        amount: '1 tab',
        parts: [DayPart.morning],
      );
      final report = care.reportFor(care.pets.first.id, 7);
      expect(report.lines, isNotEmpty);
      expect(care.canShareVetReport, isFalse);
    });
  });
}
