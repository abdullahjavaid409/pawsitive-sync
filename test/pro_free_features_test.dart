import 'package:flutter_test/flutter_test.dart';
import 'package:pawsitive_sync/core/constants/pet_limits.dart';
import 'package:pawsitive_sync/core/logging/app_log.dart';
import 'package:pawsitive_sync/data/care_repository.dart';
import 'package:pawsitive_sync/domain/models.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_log_helpers.dart';

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
      await care.addMedication(
        petId: care.pets.first.id,
        name: 'Daily',
        amount: '1 tab',
        parts: [DayPart.morning, DayPart.evening],
      );
      final morning = care.doses.firstWhere(
        (d) => d.name == 'Daily' && d.part == DayPart.morning,
      );
      final evening = care.doses.firstWhere(
        (d) => d.name == 'Daily' && d.part == DayPart.evening,
      );
      expect(await care.logDose(
        doseId: morning.id,
        memberId: 'you',
        amount: '1 tab',
        timeLabel: '8:00 AM',
      ), isTrue);
      expect(await care.markDoseUncertain(evening.id), isTrue);
      expectLogged('dose.log.completed');
      expectLogged('dose.uncertain.completed');
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
    test('startTrial opens all gates', () async {
      final care = await careWithOnePet();
      await care.startTrial();

      expect(care.isPro, isTrue);
      expect(care.canInviteHousehold, isTrue);
      expect(care.canShareVetReport, isTrue);
      expect(care.canShowLowSupplyAlerts, isTrue);
      expect(care.canAddPet, isTrue);
      expectLogged('billing.pro.unlocked', fields: {'source': 'trial'});
    });

    test('second pet allowed on Pro', () async {
      final care = await careWithOnePet();
      await care.startTrial();
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
      await care.startTrial();
      await lowSupplyMed(care);
      expect(care.canShowLowSupplyAlerts, isTrue);
      expect(care.lowSupply, isNotNull);
    });

    test('Pro respects 10-pet household cap', () async {
      final care = CareRepository.sample();
      await care.startTrial();
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
      await care.startTrial();
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
