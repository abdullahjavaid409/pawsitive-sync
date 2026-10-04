import 'package:flutter_test/flutter_test.dart';
import 'package:pawsitive_sync/core/constants/live_features.dart';
import 'package:pawsitive_sync/core/logging/app_log.dart';
import 'package:pawsitive_sync/data/care_repository.dart';
import 'package:pawsitive_sync/data/household_api.dart';
import 'package:pawsitive_sync/data/household_store.dart';
import 'package:pawsitive_sync/data/push_service.dart';
import 'package:pawsitive_sync/domain/models.dart';
import 'package:pawsitive_sync/ui/onboarding/onboarding_view_model.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_household_api.dart';

/// Exercises every live repository feature once and asserts required logs.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppLog.enableTestCapture();
  });

  tearDown(AppLog.disableTestCapture);

  test('registry lists every live feature', () {
    expect(LiveFeatures.coverage.length, greaterThanOrEqualTo(15));
    expect(LiveFeatures.allRequiredLogs, isNotEmpty);
    for (final feature in LiveFeatures.coverage) {
      expect(feature.id, isNotEmpty, reason: feature.name);
      expect(feature.name, isNotEmpty);
    }
  });

  test('all live repository features log required events', () async {
    await _exerciseAllLiveFeatures();
    for (final log in LiveFeatures.allRequiredLogs) {
      expect(
        AppLog.logged(log),
        isTrue,
        reason: 'Missing log for live feature: $log',
      );
    }
  });
}

Future<void> _exerciseAllLiveFeatures() async {
  DateTime clock() => DateTime(2026, 10, 3, 14);
  final care = CareRepository(clock: clock, store: HouseholdStore());
  await care.addPet(name: 'Milo', species: Species.cat);
  await care.flushPersist();
  await CareRepository(clock: clock, store: HouseholdStore()).restore();
  final petId = care.pets.first.id;

  // Pets
  await care.addPet(name: '  ', species: Species.cat);
  await care.addPet(name: 'Juniper', species: Species.dog);
  await care.updatePet(petId: 'ghost', name: 'X', species: Species.cat);
  final pet = care.pets.first;
  await care.updatePet(
    petId: pet.id,
    name: pet.name,
    species: pet.species,
    ageYears: pet.ageYears,
    weightKg: pet.weightKg,
    conditions: pet.conditions,
  );
  await care.updatePet(petId: pet.id, name: 'Milo Jr', species: Species.cat);

  // Medications
  await care.addMedication(
    petId: petId,
    name: ' ',
    amount: '1 tab',
    parts: [DayPart.morning],
  );
  // Pro for setup only: Free schedules the morning dose only.
  care.debugStorePro = true;
  await care.addMedication(
    petId: petId,
    name: 'Insulin',
    amount: '2 u',
    parts: [DayPart.morning, DayPart.evening],
    supplyTotal: 30,
  );
  care.debugStorePro = false;
  await care.addMedication(
    petId: 'missing',
    name: 'Test',
    amount: '1 tab',
    parts: [DayPart.morning],
  );
  final med = care.medications.lastWhere((m) => m.name == 'Insulin');
  await care.refill(med.id);
  final morning = care.doses.firstWhere(
    (d) => d.name == 'Insulin' && d.part == DayPart.morning,
  );
  final evening = care.doses.firstWhere(
    (d) => d.name == 'Insulin' && d.part == DayPart.evening,
  );
  await care.markDoseUncertain(morning.id);
  await care.skipDose(evening.id);
  await care.logDose(
    doseId: morning.id,
    memberId: 'you',
    amount: morning.amount,
    timeLabel: '2:00 PM',
  );
  await care.logDose(
    doseId: morning.id,
    memberId: 'you',
    amount: morning.amount,
    timeLabel: '2:05 PM',
  );
  await care.removeMedication(med.id);

  // Care events
  await care.addCareEvent(
    petId: 'missing',
    title: 'Vet',
    kind: CareEventKind.vetVisit,
    dueDate: care.now,
  );
  await care.addCareEvent(
    petId: petId,
    title: 'Checkup',
    kind: CareEventKind.vetVisit,
    dueDate: care.now.add(const Duration(days: 3)),
  );
  await care.removeCareEvent(care.careEvents.single.id);

  // Billing / Pro
  await care.setPlan(BillingPlan.monthly);
  care.applyStoreEntitlement(true, BillingPlan.yearly);
  await care.restoreBilling();

  // Onboarding (separate instance)
  final onboard = CareRepository(clock: clock);
  onboard.applyOnboarding(
    OnboardingViewModel()
      ..setName('Buddy')
      ..setSpecies(Species.dog),
  );

  // Household skips (offline)
  await care.connect();
  await care.join(code: 'ABC', name: 'Alex');
  await care.join(code: 'ABCDEF', name: 'Alex');
  await care.sync();

  // Join household
  final joinAdapter = FakeHouseholdAdapter([
    (201, {...connectHouseholdBody(), 'token': 'join-token'}),
    (200, {'ok': true}),
  ]);
  final joiner = CareRepository(
    api: fakeHouseholdApi(joinAdapter),
    clock: clock,
  );
  await joiner.join(code: 'ABC234', name: 'Partner');

  // Connected household + sitter + sync + failure
  final adapter = FakeHouseholdAdapter([
    (201, connectHouseholdBody()),
    (200, {'ok': true}),
    (
      201,
      {
        'token': 'sitter-tok',
        'expiresAt': '2026-11-03T00:00:00.000Z',
        'url': '/sitter#t=sitter-tok',
      },
    ),
    (
      200,
      connectHouseholdBody(
        logs: [
          {
            'id': 'log-partner-1',
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
    (503, {'error': 'busy'}),
    (403, {'error': 'Browser sitter links need Pawsitive Pro.'}),
  ]);
  final connected = CareRepository(
    api: fakeHouseholdApi(adapter),
    clock: clock,
  );
  await connected.addPet(name: 'Miso', species: Species.cat);
  connected.applyStoreEntitlement(true, BillingPlan.yearly);
  await connected.connect();
  await connected.ensureSitterWebLink();
  await connected.sync(force: true);
  await connected.sync(force: true);

  // Subscriber shares Pro with a Free household
  final shareAdapter = FakeHouseholdAdapter([
    (201, connectHouseholdBody(isPro: false)),
    (200, {'ok': true}),
    (200, {'isPro': true, 'plan': 'yearly'}),
  ]);
  final sharer = CareRepository(
    api: fakeHouseholdApi(shareAdapter),
    clock: clock,
  );
  await sharer.addPet(name: 'Miso', species: Species.cat);
  await sharer.connect();
  sharer.applyStoreEntitlement(true, BillingPlan.yearly);
  await sharer.startTrial();

  // Cached sitter link
  SharedPreferences.setMockInitialValues({
    'sitter_web_token_v1:ABC234': 'cached-sitter-token',
  });
  final cached = CareRepository(
    api: fakeHouseholdApi(
      FakeHouseholdAdapter([
        (201, connectHouseholdBody(inviteCode: 'ABC234')),
        (200, {'ok': true}),
      ]),
    ),
    clock: clock,
  );
  await cached.addPet(name: 'Miso', species: Species.cat);
  cached.applyStoreEntitlement(true, BillingPlan.yearly);
  await cached.connect();
  await cached.ensureSitterWebLink();

  // Sitter link API failure (force bypasses cache from earlier connects)
  final failAdapter = FakeHouseholdAdapter([
    (201, connectHouseholdBody(inviteCode: 'FAIL01')),
    (200, {'ok': true}),
    (403, {'error': 'Browser sitter links need Pawsitive Pro.'}),
  ]);
  final failLink = CareRepository(
    api: fakeHouseholdApi(failAdapter),
    clock: clock,
  );
  await failLink.addPet(name: 'Miso', species: Species.cat);
  failLink.applyStoreEntitlement(true, BillingPlan.yearly);
  await failLink.connect();
  await failLink.ensureSitterWebLink(force: true);

  // Sitter skips (free / offline)
  final free = CareRepository(clock: clock);
  await free.addPet(name: 'A', species: Species.cat);
  await free.ensureSitterWebLink();

  // Push
  await PushService.registerIfConnected(null);
  await PushService.registerIfConnected(
    HouseholdApi(Uri.parse('https://x.test')),
  );
  await PushService.setHouseholdPushEnabled(false);
  await PushService.notifyPartnerLogged(
    logId: '',
    who: 'Dan',
    medicationName: 'Insulin',
    petName: 'Miso',
  );

  // Pro reset
  await care.reset();
}
