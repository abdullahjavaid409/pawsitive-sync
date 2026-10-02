import 'package:flutter/foundation.dart';
import 'package:pawsitive_sync/core/logging/app_log.dart';
import 'package:pawsitive_sync/data/household_api.dart';
import 'package:pawsitive_sync/domain/models.dart';

/// Household schedule. With an API, the server is the source of truth.
/// Without one, the sample household stays so tests and offline use still run.
class CareRepository extends ChangeNotifier {
  CareRepository({HouseholdApi? api})
    : _api = api,
      _members = List<Member>.of(api == null ? _seedMembers : const []),
      _pets = List<Pet>.of(api == null ? _seedPets : const []),
      _doses = List<Dose>.of(api == null ? _seedDoses : const []),
      _medications = List<Medication>.of(
        api == null ? _seedMedications : <Medication>[],
      ),
      _activity = List<ActivityItem>.of(api == null ? _seedActivity : const []);

  final HouseholdApi? _api;
  bool syncing = false;
  String? syncError;

  final List<Member> _members;
  final List<Pet> _pets;
  final List<Dose> _doses;
  final List<Medication> _medications;
  List<ActivityItem> _activity;
  bool _isPro = false;
  BillingPlan _plan = BillingPlan.yearly;

  bool get isPro => _isPro;

  BillingPlan get plan => _plan;

  List<Member> get members => List.unmodifiable(_members);
  List<Pet> get pets => List.unmodifiable(_pets);
  List<Dose> get doses => List.unmodifiable(_doses);
  List<Medication> get medications => List.unmodifiable(_medications);
  List<ActivityItem> get activity => List.unmodifiable(_activity);

  Member memberById(String id) =>
      _members.firstWhere((member) => member.id == id);

  Pet petById(String id) => _pets.firstWhere((pet) => pet.id == id);

  Dose? doseById(String id) {
    for (final dose in _doses) {
      if (dose.id == id) return dose;
    }
    return null;
  }

  Medication? medicationById(String id) {
    for (final medication in _medications) {
      if (medication.id == id) return medication;
    }
    return null;
  }

  int get givenCount =>
      _doses.where((dose) => dose.status == DoseStatus.given).length;

  Dose? get nextDue {
    for (final dose in _doses) {
      if (dose.status == DoseStatus.due) return dose;
    }
    return null;
  }

  Medication? get lowSupply {
    for (final medication in _medications) {
      if (medication.isLow) return medication;
    }
    return null;
  }

  /// Fetches the household once. Does nothing when no API is configured.
  Future<void> sync() async {
    final api = _api;
    if (api == null) return;
    syncing = true;
    syncError = null;
    notifyListeners();
    try {
      final house = await api.fetchHousehold();
      _members
        ..clear()
        ..addAll(house.members);
      _pets
        ..clear()
        ..addAll(house.pets);
      _doses
        ..clear()
        ..addAll(house.doses);
      _medications
        ..clear()
        ..addAll(house.medications);
      _activity = house.activity;
      _isPro = house.isPro;
      _plan = house.plan;
      AppLog.event('household.synced', {'doses': _doses.length});
    } catch (_) {
      syncError =
          "Can't reach the household. Check the connection and try again.";
      AppLog.event('household.sync_failed');
    } finally {
      syncing = false;
      notifyListeners();
    }
  }

  Future<bool> logDose({
    required String doseId,
    required String memberId,
    required String amount,
    required String timeLabel,
    DoseOutcome? outcome,
  }) async {
    final api = _api;
    if (api != null) {
      try {
        final saved = await api.logDose(
          doseId: doseId,
          memberId: memberId,
          amount: amount,
          timeLabel: timeLabel,
          outcome: outcome == null || outcome == DoseOutcome.smooth
              ? null
              : outcome.name,
        );
        final index = _doses.indexWhere((dose) => dose.id == doseId);
        if (index >= 0) _doses[index] = saved.dose;
        _activity = [saved.activity, ..._activity];
        notifyListeners();
        AppLog.event('dose.logged', {
          'doseId': doseId,
          'memberId': memberId,
          'outcome': outcome?.name ?? 'smooth',
        });
        return true;
      } catch (_) {
        AppLog.event('dose.log_failed', {'doseId': doseId});
        return false;
      }
    }
    final index = _doses.indexWhere((dose) => dose.id == doseId);
    if (index < 0) {
      AppLog.event('dose.log_rejected', {'doseId': doseId});
      return false;
    }
    final dose = _doses[index];
    final member = memberById(memberId);
    final pet = petById(dose.petId);
    final who = member.isYou ? 'You' : member.name;
    _doses[index] = dose.copyWith(
      status: DoseStatus.given,
      amount: amount,
      givenById: memberId,
      subtitle: '${pet.name} · $who, $timeLabel',
    );
    _activity = [
      ActivityItem(
        memberId: memberId,
        actor: who,
        action: 'gave ${pet.name}',
        emphasis: dose.copyWith(amount: amount).title,
        timeLabel: timeLabel,
        note: switch (outcome) {
          DoseOutcome.vomited => 'Vomited a little after the dose',
          DoseOutcome.partial => 'Partial dose',
          DoseOutcome.lowAppetite => 'Low appetite',
          DoseOutcome.smooth || null => null,
        },
      ),
      ..._activity,
    ];
    notifyListeners();
    AppLog.event('dose.logged', {
      'doseId': doseId,
      'memberId': memberId,
      'outcome': outcome?.name ?? 'smooth',
    });
    return true;
  }

  Future<bool> skipDose(String doseId) async {
    final api = _api;
    if (api != null) {
      try {
        await api.skipDose(doseId);
      } catch (_) {
        AppLog.event('dose.skip_failed', {'doseId': doseId});
        return false;
      }
    }
    final removed = _doses.length;
    _doses.removeWhere((dose) => dose.id == doseId);
    if (_doses.length == removed) {
      AppLog.event('dose.skip_rejected', {'doseId': doseId});
      return false;
    }
    notifyListeners();
    AppLog.event('dose.skipped', {'doseId': doseId});
    return true;
  }

  Future<bool> refill(String medicationId) async {
    final api = _api;
    if (api != null) {
      try {
        final saved = await api.refill(medicationId);
        final index = _medications.indexWhere((item) => item.id == medicationId);
        if (index >= 0) _medications[index] = saved;
        notifyListeners();
        AppLog.event('medication.refilled', {'medicationId': medicationId});
        return true;
      } catch (_) {
        AppLog.event('medication.refill_failed', {'medicationId': medicationId});
        return false;
      }
    }
    final index = _medications.indexWhere((item) => item.id == medicationId);
    if (index < 0) {
      AppLog.event('medication.refill_rejected', {
        'medicationId': medicationId,
      });
      return false;
    }
    final medication = _medications[index];
    _medications[index] = medication.copyWith(
      dosesLeft: medication.supplyTotal,
    );
    notifyListeners();
    AppLog.event('medication.refilled', {'medicationId': medicationId});
    return true;
  }

  Future<void> setPlan(BillingPlan value) async {
    if (_plan == value && _api == null) return;
    final api = _api;
    if (api != null) {
      try {
        _plan = await api.setPlan(value);
      } catch (_) {
        AppLog.event('billing.plan_failed', {'plan': value.name});
        return;
      }
    } else {
      _plan = value;
    }
    notifyListeners();
    AppLog.event('billing.plan_set', {'plan': _plan.name});
  }

  Future<void> startTrial() async {
    final api = _api;
    if (api != null) {
      try {
        final billing = await api.startTrial();
        _isPro = billing.isPro;
        _plan = billing.plan;
      } catch (_) {
        AppLog.event('billing.trial_failed');
        return;
      }
    } else {
      _isPro = true;
    }
    notifyListeners();
    AppLog.event('billing.trial_started');
  }

  static const _seedMembers = [
    Member(
      id: 'you',
      name: 'You',
      initials: 'You',
      role: MemberRole.owner,
      avatarTone: AvatarTone.brand,
      isYou: true,
    ),
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
      status: 'On duty tonight',
    ),
    Member(
      id: 'priya',
      name: 'Priya',
      initials: 'P',
      role: MemberRole.sitter,
      avatarTone: AvatarTone.neutral,
      status: 'Oct 5 – Oct 12',
    ),
  ];

  static const _seedPets = [
    Pet(
      id: 'miso',
      name: 'Miso',
      species: Species.cat,
      ageYears: 12,
      breed: 'Domestic shorthair',
      sex: 'female',
      conditions: ['Diabetes', 'Kidney disease'],
      weightKg: 4.6,
      onTimePercent: 97,
      dailyMeds: 3,
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
      onTimePercent: 100,
      dailyMeds: 1,
    ),
  ];

  static const _seedDoses = [
    Dose(
      id: 'insulin-am',
      petId: 'miso',
      medicationId: 'insulin',
      name: 'Insulin',
      amount: '2 units',
      part: DayPart.morning,
      status: DoseStatus.given,
      subtitle: 'Miso · Sara, 8:02 AM',
      givenById: 'sara',
    ),
    Dose(
      id: 'benazepril-am',
      petId: 'miso',
      medicationId: 'benazepril',
      name: 'Benazepril',
      amount: '2.5 mg',
      part: DayPart.morning,
      status: DoseStatus.given,
      subtitle: 'Miso · Sara, 8:04 AM',
      givenById: 'sara',
    ),
    Dose(
      id: 'joint-am',
      petId: 'juniper',
      medicationId: 'joint',
      name: 'Joint supplement',
      amount: '',
      part: DayPart.morning,
      status: DoseStatus.given,
      subtitle: 'Juniper · Dan, 8:30 AM',
      givenById: 'dan',
    ),
    Dose(
      id: 'fluids-pm',
      petId: 'miso',
      medicationId: 'fluids',
      name: 'Fluids',
      amount: '100 ml',
      part: DayPart.afternoon,
      status: DoseStatus.due,
      subtitle: 'Miso · due 1:00 PM',
    ),
    Dose(
      id: 'insulin-pm',
      petId: 'miso',
      medicationId: 'insulin',
      name: 'Insulin',
      amount: '2 units',
      part: DayPart.evening,
      status: DoseStatus.upcoming,
      subtitle: 'Miso · 8:00 PM with food · Dan',
    ),
  ];

  static final _seedMedications = [
    Medication(
      id: 'benazepril',
      petId: 'miso',
      name: 'Benazepril',
      detail: '2.5 mg tablet · Miso · kidney support',
      doseLabel: '1 tablet',
      whenLabel: 'Daily, 8:00 AM',
      fallbackLabel: 'Ping Sara after 30 min',
      dosesLeft: 4,
      supplyTotal: 30,
      lastsUntil: 'Tue, Oct 6',
      onTimeLabel: '29 of 30 on time this month',
      history: const [
        DoseLog(when: 'Today · 8:04 AM', who: 'Sara'),
        DoseLog(when: 'Thu · 8:11 AM', who: 'Dan'),
        DoseLog(when: 'Wed · 9:40 AM', who: 'You', lateNote: '1h 40m late'),
      ],
    ),
  ];

  static const _seedActivity = [
    ActivityItem(
      memberId: 'sara',
      actor: 'Sara',
      action: 'gave Miso',
      emphasis: 'Insulin · 2 units',
      timeLabel: '8:02 AM',
    ),
    ActivityItem(
      memberId: 'sara',
      actor: 'Sara',
      action: 'gave Miso',
      emphasis: 'Benazepril',
      timeLabel: '8:04 AM',
    ),
    ActivityItem(
      memberId: 'dan',
      actor: 'Dan',
      action: 'noted for Miso',
      emphasis: '',
      timeLabel: '8:20 AM',
      note: 'Vomited a little after breakfast',
    ),
  ];
}
