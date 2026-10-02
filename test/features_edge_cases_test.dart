import 'package:flutter_test/flutter_test.dart';
import 'package:pawsitive_sync/core/constants/pet_limits.dart';
import 'package:pawsitive_sync/core/logging/app_log.dart';
import 'package:pawsitive_sync/data/care_repository.dart';
import 'package:pawsitive_sync/data/household_api.dart';
import 'package:pawsitive_sync/domain/models.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppLog.enableTestCapture();
  });

  tearDown(AppLog.disableTestCapture);

  group('Pro vs Free', () {
    test('free tier blocks a second pet when sample already has two', () {
      final care = CareRepository.sample();
      expect(care.isPro, isFalse);
      expect(care.pets.length, 2);
      expect(care.canAddPet, isFalse);
    });

    test('pro trial unlocks adding more pets', () async {
      final care = CareRepository.sample();
      await care.startTrial();
      expect(care.isPro, isTrue);
      expect(care.canAddPet, isTrue);
    });

    test('pro tier respects household pet cap', () async {
      final care = CareRepository.sample();
      await care.startTrial();
      for (var i = 0; i < PetLimits.maxPetsPerHousehold - 2; i++) {
        final id = await care.addPet(name: 'Pet $i', species: Species.cat);
        expect(id, isNotNull);
      }
      expect(care.pets.length, PetLimits.maxPetsPerHousehold);
      expect(care.canAddPet, isFalse);
    });
  });

  group('Medication course end', () {
    test('medication with endDay is inactive after course ends', () async {
      final clock = () => DateTime(2026, 10, 10, 14);
      final care = CareRepository.sample(clock: clock);
      final endDay = dayKey(clock().add(const Duration(days: 7)));
      await care.addMedication(
        petId: 'miso',
        name: 'Antibiotic',
        amount: '1 tablet',
        parts: [DayPart.morning],
        endDay: endDay,
      );
      final med = care.medications.last;
      expect(med.isActiveOn(dayKey(clock())), isTrue);
      expect(med.isActiveOn(endDay), isTrue);
      expect(
        med.isActiveOn(dayKey(clock().add(const Duration(days: 8)))),
        isFalse,
      );
    });

    test('ended medication does not appear in today doses', () async {
      final clock = () => DateTime(2026, 10, 20, 14);
      final care = CareRepository.sample(clock: clock);
      await care.addMedication(
        petId: 'miso',
        name: 'Short course',
        amount: '1 tablet',
        parts: [DayPart.morning],
        endDay: dayKey(DateTime(2026, 10, 19)),
      );
      expect(
        care.doses.any((d) => d.name == 'Short course'),
        isFalse,
      );
    });
  });

  group('Dose logging edge cases', () {
    test('uncertain dose stays due with check-first subtitle', () async {
      final care = CareRepository.sample(
        clock: () => DateTime(2026, 10, 3, 14),
      );
      final dose = care.doses.firstWhere((d) => d.status == DoseStatus.due);
      final ok = await care.markDoseUncertain(dose.id);
      expect(ok, isTrue);
      final updated = care.doseById(dose.id)!;
      expect(updated.status, DoseStatus.due);
      expect(updated.subtitle, contains('not sure'));
    });

    test('given dose can replace uncertain log', () async {
      final care = CareRepository.sample(
        clock: () => DateTime(2026, 10, 3, 14),
      );
      final dose = care.doses.firstWhere((d) => d.status == DoseStatus.due);
      await care.markDoseUncertain(dose.id);
      final ok = await care.logDose(
        doseId: dose.id,
        memberId: 'you',
        amount: dose.amount,
        timeLabel: '2:00 PM',
      );
      expect(ok, isTrue);
      expect(care.doseById(dose.id)!.status, DoseStatus.given);
    });

    test('double log of same dose is rejected', () async {
      final care = CareRepository.sample(
        clock: () => DateTime(2026, 10, 3, 14),
      );
      final dose = care.doses.firstWhere((d) => d.status == DoseStatus.due);
      final first = await care.logDose(
        doseId: dose.id,
        memberId: 'you',
        amount: dose.amount,
        timeLabel: '2:00 PM',
      );
      expect(first, isTrue);
      final second = await care.logDose(
        doseId: dose.id,
        memberId: 'you',
        amount: dose.amount,
        timeLabel: '2:05 PM',
      );
      expect(second, isFalse);
      expect(care.lastError, isNotNull);
    });

    test('skip removes dose from today list', () async {
      final care = CareRepository.sample(
        clock: () => DateTime(2026, 10, 3, 14),
      );
      final dose = care.doses.firstWhere((d) => d.status == DoseStatus.due);
      final ok = await care.skipDose(dose.id);
      expect(ok, isTrue);
      expect(care.doseById(dose.id), isNull);
    });
  });

  group('Care events', () {
    test('adds and lists upcoming care events', () async {
      final clock = () => DateTime(2026, 10, 3);
      final care = CareRepository.sample(clock: clock);
      final ok = await care.addCareEvent(
        petId: 'miso',
        title: 'Rabies booster',
        kind: CareEventKind.vaccine,
        dueDate: clock().add(const Duration(days: 14)),
      );
      expect(ok, isTrue);
      final upcoming = care.upcomingCareEvents(withinDays: 60);
      expect(upcoming, hasLength(1));
      expect(upcoming.first.title, 'Rabies booster');
      expect(upcoming.first.kind, CareEventKind.vaccine);
    });

    test('rejects care event without pet', () async {
      final care = CareRepository.sample();
      final ok = await care.addCareEvent(
        petId: 'missing',
        title: 'Vet visit',
        kind: CareEventKind.vetVisit,
        dueDate: DateTime(2026, 11, 1),
      );
      expect(ok, isFalse);
    });

    test('removeCareEvent drops item from upcoming list', () async {
      final care = CareRepository.sample();
      await care.addCareEvent(
        petId: 'miso',
        title: 'Checkup',
        kind: CareEventKind.vetVisit,
        dueDate: care.now.add(const Duration(days: 3)),
      );
      final event = care.careEvents.single;
      await care.removeCareEvent(event.id);
      expect(care.upcomingCareEvents(), isEmpty);
    });
  });

  group('Household join validation', () {
    test('rejects short invite code', () async {
      final care = CareRepository.sample();
      final error = await care.join(code: 'ABC', name: 'Alex');
      expect(error, isNotNull);
    });

    test('rejects empty name', () async {
      final care = CareRepository.sample();
      final error = await care.join(code: 'ABCDEF', name: '  ');
      expect(error, isNotNull);
    });
  });

  group('Local-first & minimal API', () {
    test('all care works offline with no API', () async {
      final care = CareRepository(clock: () => DateTime(2026, 10, 3, 14));
      final petId = await care.addPet(name: 'Solo', species: Species.cat);
      expect(petId, isNotNull);
      expect(
        AppLog.testRecords.any(
          (r) => r.name == 'pet.add.completed' && r.fields['offline'] == true,
        ),
        isTrue,
      );
      await care.addMedication(
        petId: petId!,
        name: 'Daily pill',
        amount: '1 tablet',
        parts: [DayPart.morning],
      );
      final dose = care.doses.firstWhere((d) => d.status == DoseStatus.due);
      expect(await care.logDose(
        doseId: dose.id,
        memberId: 'you',
        amount: '1 tablet',
        timeLabel: '8:00 AM',
      ), isTrue);
      await care.sync();
      expect(AppLog.logged('household.sync_skipped'), isTrue);
    });

    test('sync skipped when not connected even with API configured', () async {
      final care = CareRepository(
        api: HouseholdApi(Uri.parse('https://example.test')),
        clock: () => DateTime(2026, 10, 3, 14),
      );
      await care.sync();
      expect(AppLog.logged('household.sync_skipped'), isTrue);
    });
  });

  group('Medication validation', () {
    test('rejects empty name', () async {
      final care = CareRepository.sample();
      final ok = await care.addMedication(
        petId: 'miso',
        name: '  ',
        amount: '1 tablet',
        parts: [DayPart.morning],
      );
      expect(ok, isFalse);
    });

    test('rejects empty schedule parts', () async {
      final care = CareRepository.sample();
      final ok = await care.addMedication(
        petId: 'miso',
        name: 'Test med',
        amount: '1 tablet',
        parts: [],
      );
      expect(ok, isFalse);
    });

    test('refill restores supply count', () async {
      final care = CareRepository.sample();
      final med = care.medications.firstWhere((m) => m.tracksSupply);
      final ok = await care.refill(med.id);
      expect(ok, isTrue);
      expect(care.medicationById(med.id)!.dosesLeft, med.supplyTotal);
    });
  });
}
