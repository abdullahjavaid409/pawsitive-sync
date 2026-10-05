import 'package:pawsitive_sync/data/care_repository.dart';
import 'package:pawsitive_sync/data/household_api.dart';
import 'package:pawsitive_sync/domain/models.dart';

/// Test-only household: two pets (Miso, Juniper), two caregivers (Sara,
/// Dan), four medicines and this morning’s doses already logged. Free tier.
/// Lives in `test/` so no made-up data ever ships in the app.
CareRepository sampleCare({HouseholdApi? api, DateTime Function()? clock}) {
  final care = CareRepository(
    api: api,
    clock: clock ?? () => DateTime(2026, 10, 2, 13, 6),
  );
  loadSampleHousehold(care);
  return care;
}

/// Replaces [care]'s household with the sample one (dates from its clock).
void loadSampleHousehold(CareRepository care) {
  final today = dayKey(care.now);
  care.debugLoadHousehold(
    members: const [
      Member(
        id: 'sara',
        name: 'Sara',
        initials: 'S',
        role: MemberRole.caregiver,
        avatarTone: AvatarTone.soft,
        status: 'Active now',
        active: true,
      ),
      Member(
        id: 'dan',
        name: 'Dan',
        initials: 'D',
        role: MemberRole.caregiver,
        avatarTone: AvatarTone.neutral,
      ),
    ],
    pets: const [
      Pet(
        id: 'miso',
        name: 'Miso',
        species: Species.cat,
        ageYears: 12,
        breed: 'Domestic shorthair',
        sex: 'female',
        conditions: ['Diabetes', 'Kidney disease'],
        weightKg: 4.6,
        onTimePercent: 0,
        dailyMeds: 0,
      ),
      Pet(
        id: 'juniper',
        name: 'Juniper',
        species: Species.dog,
        ageYears: 8,
        breed: 'Mixed breed',
        sex: 'female',
        conditions: ['Arthritis'],
        weightKg: 18.2,
        onTimePercent: 0,
        dailyMeds: 0,
      ),
    ],
    medications: [
      Medication(
        id: 'insulin',
        petId: 'miso',
        name: 'Insulin',
        amount: '2 units',
        parts: const [DayPart.morning, DayPart.evening],
        supplyTotal: 0,
        dosesLeft: 0,
        startDay: today,
      ),
      Medication(
        id: 'benazepril',
        petId: 'miso',
        name: 'Benazepril',
        amount: '2.5 mg',
        parts: const [DayPart.morning],
        supplyTotal: 30,
        dosesLeft: 4,
        startDay: today,
      ),
      Medication(
        id: 'joint',
        petId: 'juniper',
        name: 'Joint supplement',
        amount: '',
        parts: const [DayPart.morning],
        supplyTotal: 0,
        dosesLeft: 0,
        startDay: today,
      ),
      Medication(
        id: 'fluids',
        petId: 'miso',
        name: 'Fluids',
        amount: '100 ml',
        parts: const [DayPart.afternoon],
        supplyTotal: 0,
        dosesLeft: 0,
        startDay: today,
      ),
    ],
    logs: [
      DoseRecord(
        id: 'log-joint',
        medicationId: 'joint',
        part: DayPart.morning,
        day: today,
        memberId: 'dan',
        outcome: LogOutcome.given,
        amount: '',
        timeLabel: '8:30 AM',
      ),
      DoseRecord(
        id: 'log-benazepril',
        medicationId: 'benazepril',
        part: DayPart.morning,
        day: today,
        memberId: 'sara',
        outcome: LogOutcome.given,
        amount: '2.5 mg',
        timeLabel: '8:04 AM',
      ),
      DoseRecord(
        id: 'log-insulin',
        medicationId: 'insulin',
        part: DayPart.morning,
        day: today,
        memberId: 'sara',
        outcome: LogOutcome.given,
        amount: '2 units',
        timeLabel: '8:02 AM',
      ),
    ],
  );
}
