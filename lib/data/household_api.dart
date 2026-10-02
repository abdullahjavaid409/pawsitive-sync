import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:pawsitive_sync/domain/models.dart';

/// One household snapshot from GET /v1/household.
class HouseholdSnapshot {
  const HouseholdSnapshot({
    required this.isPro,
    required this.plan,
    required this.members,
    required this.pets,
    required this.doses,
    required this.medications,
    required this.activity,
  });

  final bool isPro;
  final BillingPlan plan;
  final List<Member> members;
  final List<Pet> pets;
  final List<Dose> doses;
  final List<Medication> medications;
  final List<ActivityItem> activity;
}

class SavedDose {
  const SavedDose({required this.dose, required this.activity});

  final Dose dose;
  final ActivityItem activity;
}

/// Talks to the household API. No polling. Callers fetch once and write on an action.
class HouseholdApi {
  HouseholdApi(this.base, {http.Client? client})
    : _client = client ?? http.Client();

  final Uri base;
  final http.Client _client;

  Future<HouseholdSnapshot> fetchHousehold() async {
    final body = await _get('/v1/household');
    return HouseholdSnapshot(
      isPro: body['isPro'] == true,
      plan: _plan(body['plan']),
      members: _list(body['members'], _member),
      pets: _list(body['pets'], _pet),
      doses: _list(body['doses'], _dose),
      medications: _list(body['medications'], _medication),
      activity: _list(body['activity'], _activity),
    );
  }

  Future<SavedDose> logDose({
    required String doseId,
    required String memberId,
    required String amount,
    required String timeLabel,
    String? outcome,
  }) async {
    final body = await _post('/v1/doses/$doseId/log', {
      'memberId': memberId,
      'amount': amount,
      'timeLabel': timeLabel,
      if (outcome != null) 'outcome': outcome,
    });
    final dose = body['dose'];
    final activity = body['activity'];
    if (dose is! Map<String, dynamic> || activity is! Map<String, dynamic>) {
      throw const HouseholdException('The dose was not saved.');
    }
    return SavedDose(dose: _dose(dose), activity: _activity(activity));
  }

  Future<void> skipDose(String doseId) async {
    await _post('/v1/doses/$doseId/skip', {});
  }

  Future<Medication> refill(String medicationId) async {
    final body = await _post('/v1/medications/$medicationId/refill', {});
    final medication = body['medication'];
    if (medication is! Map<String, dynamic>) {
      throw const HouseholdException('The refill was not saved.');
    }
    return _medication(medication);
  }

  Future<BillingPlan> setPlan(BillingPlan plan) async {
    final body = await _post('/v1/billing/plan', {'plan': plan.name});
    return _plan(body['plan']);
  }

  Future<({bool isPro, BillingPlan plan})> startTrial() async {
    final body = await _post('/v1/billing/trial', {});
    return (isPro: body['isPro'] == true, plan: _plan(body['plan']));
  }

  Future<Map<String, dynamic>> _get(String path) async {
    final response = await _client
        .get(_uri(path))
        .timeout(const Duration(seconds: 8));
    return _read(response);
  }

  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, dynamic> payload,
  ) async {
    final response = await _client
        .post(
          _uri(path),
          headers: const {'content-type': 'application/json'},
          body: jsonEncode(payload),
        )
        .timeout(const Duration(seconds: 8));
    return _read(response);
  }

  Uri _uri(String path) {
    final prefix = base.path.endsWith('/')
        ? base.path.substring(0, base.path.length - 1)
        : base.path;
    return base.replace(path: '$prefix$path');
  }

  Map<String, dynamic> _read(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HouseholdException(
        'The household did not answer (${response.statusCode}).',
      );
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const HouseholdException('The household answer was not usable.');
    }
    return decoded;
  }
}

class HouseholdException implements Exception {
  const HouseholdException(this.message);

  final String message;

  @override
  String toString() => message;
}

List<T> _list<T>(Object? value, T Function(Map<String, dynamic>) map) {
  if (value is! List) return [];
  return [
    for (final item in value)
      if (item is Map<String, dynamic>) map(item),
  ];
}

Member _member(Map<String, dynamic> json) {
  return Member(
    id: '${json['id']}',
    name: '${json['name']}',
    initials: '${json['initials']}',
    role: _enum(MemberRole.values, json['role'], MemberRole.caregiver),
    avatarTone: _enum(
      AvatarTone.values,
      json['avatarTone'],
      AvatarTone.neutral,
    ),
    status: json['status'] as String?,
    active: json['active'] == true,
    isYou: json['isYou'] == true,
  );
}

Pet _pet(Map<String, dynamic> json) {
  return Pet(
    id: '${json['id']}',
    name: '${json['name']}',
    species: _enum(Species.values, json['species'], Species.other),
    ageYears: _int(json['ageYears']),
    breed: '${json['breed'] ?? ''}',
    sex: '${json['sex'] ?? ''}',
    conditions: [
      for (final item
          in json['conditions'] is List ? json['conditions'] as List : const [])
        '$item',
    ],
    weightKg: _double(json['weightKg']),
    onTimePercent: _int(json['onTimePercent']),
    dailyMeds: _int(json['dailyMeds']),
  );
}

Dose _dose(Map<String, dynamic> json) {
  return Dose(
    id: '${json['id']}',
    petId: '${json['petId']}',
    medicationId: '${json['medicationId']}',
    name: '${json['name']}',
    amount: '${json['amount'] ?? ''}',
    part: _enum(DayPart.values, json['part'], DayPart.morning),
    status: _enum(DoseStatus.values, json['status'], DoseStatus.upcoming),
    subtitle: '${json['subtitle'] ?? ''}',
    givenById: json['givenById'] as String?,
  );
}

Medication _medication(Map<String, dynamic> json) {
  return Medication(
    id: '${json['id']}',
    petId: '${json['petId']}',
    name: '${json['name']}',
    detail: '${json['detail'] ?? ''}',
    doseLabel: '${json['doseLabel'] ?? ''}',
    whenLabel: '${json['whenLabel'] ?? ''}',
    fallbackLabel: '${json['fallbackLabel'] ?? ''}',
    dosesLeft: _int(json['dosesLeft']),
    supplyTotal: _int(json['supplyTotal']),
    lastsUntil: '${json['lastsUntil'] ?? ''}',
    onTimeLabel: '${json['onTimeLabel'] ?? ''}',
    history: _list(json['history'], (item) {
      return DoseLog(
        when: '${item['when']}',
        who: '${item['who']}',
        lateNote: item['lateNote'] as String?,
      );
    }),
  );
}

ActivityItem _activity(Map<String, dynamic> json) {
  return ActivityItem(
    memberId: '${json['memberId']}',
    actor: '${json['actor']}',
    action: '${json['action']}',
    emphasis: '${json['emphasis']}',
    timeLabel: '${json['timeLabel']}',
    note: json['note'] as String?,
  );
}

T _enum<T extends Enum>(List<T> values, Object? name, T fallback) {
  for (final value in values) {
    if (value.name == name) return value;
  }
  return fallback;
}

BillingPlan _plan(Object? name) =>
    name == 'monthly' ? BillingPlan.monthly : BillingPlan.yearly;

int _int(Object? value) {
  if (value is int) return value;
  if (value is num) return value.round();
  return int.tryParse('$value') ?? 0;
}

double _double(Object? value) {
  if (value is num) return value.toDouble();
  return double.tryParse('$value') ?? 0;
}
