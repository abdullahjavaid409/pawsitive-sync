import 'package:flutter/foundation.dart';
import 'package:pawsitive_sync/core/logging/app_log.dart';
import 'package:pawsitive_sync/domain/models.dart';

/// In-memory household. This is the source of truth for the demo schedule.
class CareRepository extends ChangeNotifier {
  CareRepository()
    : _members = List<Member>.of(_seedMembers),
      _pets = List<Pet>.of(_seedPets),
      _doses = List<Dose>.of(_seedDoses),
      _medications = List<Medication>.of(_seedMedications),
      _activity = List<ActivityItem>.of(_seedActivity);

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

  void logDose({
    required String doseId,
    required String memberId,
    required String amount,
    required String timeLabel,
    DoseOutcome? outcome,
  }) {
    final index = _doses.indexWhere((dose) => dose.id == doseId);
    if (index < 0) {
      AppLog.event('dose.log_rejected', {'doseId': doseId});
      return;
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
  }

  void skipDose(String doseId) {
    final removed = _doses.length;
    _doses.removeWhere((dose) => dose.id == doseId);
    if (_doses.length == removed) {
      AppLog.event('dose.skip_rejected', {'doseId': doseId});
      return;
    }
    notifyListeners();
    AppLog.event('dose.skipped', {'doseId': doseId});
  }

  void refill(String medicationId) {
    final index = _medications.indexWhere((item) => item.id == medicationId);
    if (index < 0) {
      AppLog.event('medication.refill_rejected', {
        'medicationId': medicationId,
      });
      return;
    }
    final medication = _medications[index];
    _medications[index] = medication.copyWith(
      dosesLeft: medication.supplyTotal,
    );
    notifyListeners();
    AppLog.event('medication.refilled', {'medicationId': medicationId});
  }

  void setPlan(BillingPlan value) {
    if (_plan == value) return;
    _plan = value;
    notifyListeners();
    AppLog.event('billing.plan_set', {'plan': value.name});
  }

  void startTrial() {
    _isPro = true;
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
