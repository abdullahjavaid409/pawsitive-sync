import 'package:flutter_test/flutter_test.dart';
import 'package:pawsitive_sync/core/constants/pet_limits.dart';
import 'package:pawsitive_sync/domain/models.dart';
import 'package:pawsitive_sync/ui/pets/widgets/pet_form_sections.dart';

import 'support/sample_household.dart';

void main() {
  test('updatePet saves changes locally', () async {
    final care = sampleCare();
    final pet = care.primaryPet!;
    final ok = await care.updatePet(
      petId: pet.id,
      name: 'Miso Jr',
      species: Species.dog,
      ageYears: 13,
      weightKg: 5.2,
      conditions: const ['Diabetes', 'Thyroid'],
    );
    expect(ok, isTrue);
    final updated = care.tryPetById(pet.id)!;
    expect(updated.name, 'Miso Jr');
    expect(updated.species, Species.dog);
    expect(updated.ageYears, 13);
    expect(updated.weightKg, 5.2);
    expect(updated.conditions, ['Diabetes', 'Thyroid']);
  });

  test('updatePet rejects missing pet', () async {
    final care = sampleCare();
    final ok = await care.updatePet(
      petId: 'missing',
      name: 'Ghost',
      species: Species.cat,
    );
    expect(ok, isFalse);
    expect(care.lastError, isNotNull);
  });

  test('updatePet rejects empty name', () async {
    final care = sampleCare();
    final ok = await care.updatePet(
      petId: care.primaryPet!.id,
      name: '   ',
      species: Species.cat,
    );
    expect(ok, isFalse);
  });

  test('updatePet noop when nothing changed', () async {
    final care = sampleCare();
    final pet = care.primaryPet!;
    final ok = await care.updatePet(
      petId: pet.id,
      name: pet.name,
      species: pet.species,
      ageYears: pet.ageYears,
      weightKg: pet.weightKg,
      conditions: pet.conditions,
    );
    expect(ok, isTrue);
  });

  test('PetLimits validates weight', () {
    expect(PetLimits.isValidWeight(''), isTrue);
    expect(PetLimits.isValidWeight('4.5'), isTrue);
    expect(PetLimits.isValidWeight('999'), isFalse);
    // A comma decimal separator is accepted and parsed as a dot.
    expect(PetLimits.isValidWeight('4,5'), isTrue);
    expect(PetLimits.parseWeightKg('4,5'), 4.5);
    expect(PetLimits.isValidWeight(' 4.5 '), isTrue);
    expect(PetLimits.isValidWeight('4.555'), isFalse);
    expect(PetLimits.isValidWeight('abc'), isFalse);
    expect(PetLimits.parseWeightKg(''), isNull);
    // Age over the cap is refused at the form instead of clamped silently.
    expect(PetFormValidation.ageError(''), isNull);
    expect(PetFormValidation.ageError('12'), isNull);
    expect(PetFormValidation.ageError('99'), isNotNull);
  });
}
