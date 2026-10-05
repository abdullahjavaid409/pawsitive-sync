import 'package:flutter_test/flutter_test.dart';
import 'package:pawsitive_sync/core/constants/pet_limits.dart';
import 'package:pawsitive_sync/core/logging/app_log.dart';
import 'package:pawsitive_sync/data/care_repository.dart';
import 'package:pawsitive_sync/domain/models.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_log_helpers.dart';
import 'support/sample_household.dart';

/// Pro vs Free: one switch ([CareRepository.isPro]) gates every paid feature.
/// Safety features (dose log, uncertain, skip, double-dose) stay free.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppLog.enableTestCapture();
  });

  tearDown(AppLog.disableTestCapture);

  Future<CareRepository> careWithOnePet() async {
    final care = CareRepository(clock: () => DateTime(2026, 10, 3, 14));
    if (care.members.isEmpty) {
      await care.addPet(name: 'Milo', species: Species.cat);
    }
    expect(care.pets, hasLength(1));
    return care;
  }

  Future<Medication> lowSupplyMed(CareRepository care) async {
    await care.addMedication(
      petId: care.pets.first.id,
      name: 'Insulin',
      amount: '2 units',
      parts: [DayPart.morning],
      supplyTotal: 3,
    );
    final med = care.medications.last;
    expect(med.isLow, isTrue, reason: '3 doses left triggers low supply');
    return med;
  }

  group('Free tier — all Pro gates closed', () {
    test('single pet allowed; second pet blocked', () async {
      final care = await careWithOnePet();
      expect(care.isPro, isFalse);
      expect(care.canAddPet, isFalse);
      expect(care.canInviteHousehold, isFalse);
      expect(care.canShareVetReport, isFalse);
      expect(care.canShowLowSupplyAlerts, isFalse);

      final second = await care.addPet(name: 'Juniper', species: Species.dog);
      expect(second, isNull);
      expectLogged('pet.add.blocked', fields: {'reason': 'free_tier'});
    });

    test('low supply exists but alerts are Pro-only', () async {
      final care = await careWithOnePet();
      await lowSupplyMed(care);
      expect(care.lowSupply, isNotNull);
      expect(care.canShowLowSupplyAlerts, isFalse);
    });

    test('dose logging always free', () async {
      final care = await careWithOnePet();
      // A twice-daily schedule from when they had Pro keeps working on Free.
      care.debugStorePro = true;
      await care.addMedication(
        petId: care.pets.first.id,
        name: 'Daily',
        amount: '1 tab',
        parts: [DayPart.morning, DayPart.evening],
      );
      care.debugStorePro = false;
      final morning = care.doses.firstWhere(
        (d) => d.name == 'Daily' && d.part == DayPart.morning,
      );
      final evening = care.doses.firstWhere(
        (d) => d.name == 'Daily' && d.part == DayPart.evening,
      );
      expect(
        await care.logDose(
          doseId: morning.id,
          memberId: 'you',
          amount: '1 tab',
          timeLabel: '8:00 AM',
        ),
        isTrue,
      );
      expect(await care.markDoseUncertain(evening.id), isTrue);
      expectLogged('dose.log.completed');
      expectLogged('dose.uncertain.completed');
    });

    test('one morning medicine per pet; more opens the paywall', () async {
      final care = await careWithOnePet();
      final petId = care.pets.first.id;
      expect(care.canScheduleDoseParts([DayPart.morning]), isTrue);
      expect(care.canScheduleDoseParts([DayPart.evening]), isFalse);
      expect(
        care.canScheduleDoseParts([DayPart.morning, DayPart.evening]),
        isFalse,
      );

      // Afternoon/evening doses are Pro; nothing is saved.
      expect(
        await care.addMedication(
          petId: petId,
          name: 'Insulin',
          amount: '2 u',
          parts: [DayPart.morning, DayPart.evening],
        ),
        isFalse,
      );
      expect(care.medications, isEmpty);
      expectLogged(
        'medication.add.blocked',
        fields: {'reason': 'free_tier_times'},
      );

      expect(
        await care.addMedication(
          petId: petId,
          name: 'Daily',
          amount: '1 tab',
          parts: [DayPart.morning],
        ),
        isTrue,
      );
      expect(care.canAddMedication(petId), isFalse);
      expect(
        await care.addMedication(
          petId: petId,
          name: 'Second',
          amount: '1 tab',
          parts: [DayPart.morning],
        ),
        isFalse,
      );
      expectLogged('medication.add.blocked', fields: {'reason': 'free_tier'});
    });

    test('morning reminder stays in the morning on Free', () async {
      final care = await careWithOnePet();
      final petId = care.pets.first.id;
      expect(care.canUseDoseTime(DayPart.morning, 4 * 60), isTrue);
      expect(care.canUseDoseTime(DayPart.morning, 11 * 60 + 59), isTrue);
      expect(care.canUseDoseTime(DayPart.morning, 3 * 60 + 59), isFalse);
      expect(care.canUseDoseTime(DayPart.morning, 12 * 60), isFalse);
      expect(care.canUseDoseTime(DayPart.morning, 21 * 60), isFalse);

      // A "morning" dose at 9 PM would be a free evening reminder.
      expect(
        await care.addMedication(
          petId: petId,
          name: 'Sneaky',
          amount: '1 tab',
          parts: [DayPart.morning],
          times: {DayPart.morning: 21 * 60},
        ),
        isFalse,
      );
      expect(care.medications, isEmpty);
      expect(care.lastError, contains('4:00 AM and noon'));
      expectLogged(
        'medication.add.blocked',
        fields: {'reason': 'free_tier_time_window'},
      );

      expect(
        await care.addMedication(
          petId: petId,
          name: 'Daily',
          amount: '1 tab',
          parts: [DayPart.morning],
          times: {DayPart.morning: 7 * 60 + 15},
        ),
        isTrue,
      );
      final id = care.medications.single.id;
      expect(
        await care.setMedicationTimes(id, {DayPart.morning: 21 * 60}),
        isFalse,
      );
      expectLogged(
        'medication.times.blocked',
        fields: {'reason': 'free_tier_time_window'},
      );
      expect(care.medications.single.minuteFor(DayPart.morning), 7 * 60 + 15);
      expect(
        await care.setMedicationTimes(id, {DayPart.morning: 9 * 60}),
        isTrue,
      );
      // Back to the default time is always allowed.
      expect(await care.setMedicationTimes(id, const {}), isTrue);
    });

    test('a Pro-era schedule keeps working after Pro ends', () async {
      final care = await careWithOnePet()
        ..debugStorePro = true;
      final petId = care.pets.first.id;
      for (final name in ['Insulin', 'Gaba']) {
        await care.addMedication(
          petId: petId,
          name: name,
          amount: '1',
          parts: [DayPart.morning, DayPart.evening],
          times: {DayPart.morning: 21 * 60 + 30},
        );
      }
      care.debugStorePro = false;
      expect(care.isPro, isFalse);
      expect(care.medications, hasLength(2));
      // Every dose still shows and can be logged.
      expect(care.doses.where((d) => d.part == DayPart.evening), hasLength(2));
      final insulin = care.medications.first;
      // The late morning time saved on Pro stays; changing another part’s
      // time leaves it alone and saves.
      expect(
        await care.setMedicationTimes(insulin.id, {
          DayPart.morning: 21 * 60 + 30,
          DayPart.evening: 19 * 60,
        }),
        isTrue,
      );
      expect(insulin.minuteFor(DayPart.morning), 21 * 60 + 30);
      expect(
        care.medicationById(insulin.id)!.minuteFor(DayPart.evening),
        19 * 60,
      );
      // But nothing new beyond the Free limits.
      expect(care.canAddMedication(petId), isFalse);
    });

    test('care events and reports view are free', () async {
      final care = await careWithOnePet();
      await care.addMedication(
        petId: care.pets.first.id,
        name: 'Daily',
        amount: '1 tab',
        parts: [DayPart.morning],
      );
      expect(
        await care.addCareEvent(
          petId: care.pets.first.id,
          title: 'Vet check',
          kind: CareEventKind.vetVisit,
          dueDate: care.now.add(const Duration(days: 7)),
        ),
        isTrue,
      );
      expect(care.upcomingCareEvents(), isNotEmpty);
      expect(care.canShareVetReport, isFalse);
      expect(care.reportFor(care.pets.first.id, 7).lines, isNotEmpty);
    });
  });

  group('Pro tier — isPro unlocks every paid feature', () {
    test('every dose time and medicine', () async {
      final care = await careWithOnePet()
        ..debugStorePro = true;
      final petId = care.pets.first.id;
      for (final name in ['Insulin', 'Gaba']) {
        expect(
          await care.addMedication(
            petId: petId,
            name: name,
            amount: '1',
            parts: [DayPart.morning, DayPart.afternoon, DayPart.evening],
          ),
          isTrue,
        );
      }
      expect(care.medications, hasLength(2));
    });

    test('startTrial opens all gates', () async {
      final care = await careWithOnePet();
      care.applyStoreEntitlement(true, BillingPlan.yearly);

      expect(care.isPro, isTrue);
      expect(care.canInviteHousehold, isTrue);
      expect(care.canShareVetReport, isTrue);
      expect(care.canShowLowSupplyAlerts, isTrue);
      expect(care.canAddPet, isTrue);
      expectLogged(
        'billing.store.entitlement_changed',
        fields: {'active': true},
      );
    });

    test('second pet allowed on Pro', () async {
      final care = await careWithOnePet();
      care.applyStoreEntitlement(true, BillingPlan.yearly);
      final id = await care.addPet(name: 'Juniper', species: Species.dog);
      expect(id, isNotNull);
      expect(care.pets, hasLength(2));
      expectLogged('pet.add.completed');
    });

    test('browser sitter link blocked on free tier', () async {
      final care = await careWithOnePet();
      expect(await care.ensureSitterWebLink(), isNull);
      expectLogged('sitter.link_skipped', fields: {'reason': 'free_tier'});
    });

    test('low supply alerts enabled on Pro', () async {
      final care = await careWithOnePet();
      care.applyStoreEntitlement(true, BillingPlan.yearly);
      await lowSupplyMed(care);
      expect(care.canShowLowSupplyAlerts, isTrue);
      expect(care.lowSupply, isNotNull);
    });

    test('Pro respects 10-pet household cap', () async {
      final care = sampleCare();
      care.applyStoreEntitlement(true, BillingPlan.yearly);
      final toAdd = PetLimits.maxPetsPerHousehold - care.pets.length;
      for (var i = 0; i < toAdd; i++) {
        final id = await care.addPet(name: 'Pet $i', species: Species.cat);
        expect(id, isNotNull);
      }
      expect(care.pets.length, PetLimits.maxPetsPerHousehold);
      expect(care.canAddPet, isFalse);
      expect(care.isPro, isTrue);
      expect(care.canInviteHousehold, isTrue);
    });
  });

  group('Toggle — Free → Pro → reset', () {
    test('reset returns to Free gates', () async {
      final care = await careWithOnePet();
      care.applyStoreEntitlement(true, BillingPlan.yearly);
      expect(care.canInviteHousehold, isTrue);

      await care.reset();
      expect(care.isPro, isFalse);
      expect(care.canInviteHousehold, isFalse);
      expect(care.canShareVetReport, isFalse);
      expect(care.canShowLowSupplyAlerts, isFalse);
      expect(care.pets, isEmpty);
      expectLogged('household.reset');
    });
  });
}
