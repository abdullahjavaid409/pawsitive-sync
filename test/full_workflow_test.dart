import 'package:flutter_test/flutter_test.dart';
import 'package:pawsitive_sync/core/logging/app_log.dart';
import 'package:pawsitive_sync/data/care_repository.dart';
import 'package:pawsitive_sync/data/onboarding_state.dart';
import 'package:pawsitive_sync/domain/models.dart';
import 'package:pawsitive_sync/ui/onboarding/onboarding_view_model.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// End-to-end care journey: delete → fresh start → every feature → delete again.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppLog.enableTestCapture();
  });

  tearDown(AppLog.disableTestCapture);

  test('complete delete → setup → features → delete logs every step', () async {
    final clock = () => DateTime(2026, 10, 3, 14);
    final care = CareRepository.sample(clock: clock);
    final onboarding = OnboardingViewModel();

    // --- 1. Delete / reset (Settings → Delete account) ---
    expect(care.pets, isNotEmpty);
    await care.reset();
    expect(care.pets, isEmpty);
    expect(care.medications, isEmpty);
    expect(care.logs, isEmpty);
    expect(care.careEvents, isEmpty);
    expect(care.isPro, isFalse);
    expect(AppLog.logged('household.reset'), isTrue);

    onboarding.resetForSignOut();
    expect(onboarding.isComplete, isFalse);
    expect(onboarding.petName, isEmpty);

    // --- 2. Onboarding fresh start ---
    onboarding
      ..setName('Buddy')
      ..setSpecies(Species.dog)
      ..changeAge(4)
      ..setWeight('12')
      ..toggleCondition('Arthritis')
      ..toggleCaregiver('Just me');
    await onboarding.finish(reminders: false);
    await OnboardingState.write(true);
    expect(onboarding.isComplete, isTrue);
    expect(AppLog.logged('onboarding.finished'), isTrue);

    care.applyOnboarding(onboarding);
    final pet = care.primaryPet!;
    expect(pet.name, 'Buddy');
    expect(pet.species, Species.dog);
    expect(pet.conditions, contains('Arthritis'));
    expect(AppLog.logged('household.created_from_onboarding'), isTrue);

    // --- 3. Add medicine with course end ---
    final medOk = await care.addMedication(
      petId: pet.id,
      name: 'Carprofen',
      amount: '25 mg',
      parts: [DayPart.morning, DayPart.evening],
      supplyTotal: 20,
      endDay: dayKey(clock().add(const Duration(days: 14))),
    );
    expect(medOk, isTrue);
    expect(AppLog.logged('medication.add.completed'), isTrue);
    final med = care.medications.singleWhere((m) => m.name == 'Carprofen');
    expect(med.endDay, isNotEmpty);

    // --- 4. Log a dose ---
    final due = care.doses.firstWhere((d) => d.status == DoseStatus.due);
    final logOk = await care.logDose(
      doseId: due.id,
      memberId: 'you',
      amount: '25 mg',
      timeLabel: '2:00 PM',
    );
    expect(logOk, isTrue);
    expect(AppLog.logged('dose.log.completed'), isTrue);
    expect(care.doseById(due.id)!.status, DoseStatus.given);

    // --- 5. Uncertain → given (double-dose safety) ---
    final afternoon = care.doses.firstWhere(
      (d) => d.name == 'Carprofen' && d.part == DayPart.evening,
    );
    expect(await care.markDoseUncertain(afternoon.id), isTrue);
    expect(AppLog.logged('dose.uncertain.completed'), isTrue);
    expect(
      await care.logDose(
        doseId: afternoon.id,
        memberId: 'you',
        amount: '25 mg',
        timeLabel: '8:00 PM',
      ),
      isTrue,
    );
    expect(AppLog.logCount('dose.log.completed'), 2);

    // --- 6. Skip a dose ---
    await care.addMedication(
      petId: pet.id,
      name: 'Once daily',
      amount: '1 tablet',
      parts: [DayPart.afternoon],
    );
    final skipTarget = care.doses.firstWhere(
      (d) => d.name == 'Once daily' && d.status == DoseStatus.due,
    );
    expect(await care.skipDose(skipTarget.id), isTrue);
    expect(AppLog.logged('dose.skip.completed'), isTrue);

    // --- 7. Care event (vet / vaccine) ---
    expect(
      await care.addCareEvent(
        petId: pet.id,
        title: 'Annual checkup',
        kind: CareEventKind.vetVisit,
        dueDate: clock().add(const Duration(days: 30)),
      ),
      isTrue,
    );
    expect(AppLog.logged('care_event.added'), isTrue);
    expect(care.upcomingCareEvents(), hasLength(1));

    // --- 8. Pro unlock + second pet ---
    expect(care.canAddPet, isFalse);
    await care.startTrial();
    expect(care.isPro, isTrue);
    expect(AppLog.logged('billing.pro.unlocked'), isTrue);
    final secondId = await care.addPet(name: 'Miso', species: Species.cat);
    expect(secondId, isNotNull);
    expect(AppLog.logged('pet.add.completed'), isTrue);
    expect(care.pets, hasLength(2));

    // --- 9. Update pet ---
    expect(
      await care.updatePet(
        petId: pet.id,
        name: 'Buddy Jr',
        species: Species.dog,
        ageYears: 5,
        weightKg: 13,
        conditions: ['Arthritis', 'Anxiety'],
      ),
      isTrue,
    );
    expect(care.tryPetById(pet.id)!.name, 'Buddy Jr');

    // --- 10. Refill + stop medicine ---
    expect(await care.refill(med.id), isTrue);
    expect(AppLog.logged('medication.refill.completed'), isTrue);
    expect(await care.removeMedication(med.id), isTrue);
    expect(AppLog.logged('medication.remove.completed'), isTrue);

    // --- 11. Remove care event ---
    final event = care.careEvents.single;
    await care.removeCareEvent(event.id);
    expect(AppLog.logged('care_event.removed'), isTrue);
    expect(care.upcomingCareEvents(), isEmpty);

    // --- 12. Final delete — back to welcome state ---
    await care.reset();
    await OnboardingState.clear();
    onboarding.resetForSignOut();
    expect(care.pets, isEmpty);
    expect(onboarding.isComplete, isFalse);
    expect(AppLog.logCount('household.reset'), 2);

    // Every major feature emitted at least one log in this journey.
    for (final event in [
      'household.reset',
      'onboarding.finished',
      'household.created_from_onboarding',
      'medication.add.completed',
      'dose.log.completed',
      'dose.uncertain.completed',
      'dose.skip.completed',
      'care_event.added',
      'billing.pro.unlocked',
      'pet.add.completed',
      'medication.refill.completed',
      'medication.remove.completed',
      'care_event.removed',
    ]) {
      expect(AppLog.logged(event), isTrue, reason: 'missing log: $event');
    }
  });

  test('reset clears persisted care events', () async {
    final care = CareRepository.sample();
    await care.addCareEvent(
      petId: care.primaryPet!.id,
      title: 'Vaccine',
      kind: CareEventKind.vaccine,
      dueDate: care.now.add(const Duration(days: 7)),
    );
    expect(care.careEvents, isNotEmpty);
    await care.reset();
    expect(care.careEvents, isEmpty);
    final restored = CareRepository.sample();
    await restored.restore();
    expect(restored.careEvents, isEmpty);
  });
}
