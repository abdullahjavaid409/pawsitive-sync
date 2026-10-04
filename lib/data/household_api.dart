import 'package:characters/characters.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:pawsitive_sync/core/logging/app_log.dart';
import 'package:pawsitive_sync/data/api/api_interceptors.dart';
import 'package:pawsitive_sync/data/sync_outbox.dart';
import 'package:pawsitive_sync/domain/models.dart';

/// Everything the household API knows, from GET /v1/household.
class HouseholdSnapshot {
  const HouseholdSnapshot({
    required this.inviteCode,
    required this.isPro,
    required this.plan,
    required this.memberId,
    required this.members,
    required this.pets,
    required this.medications,
    required this.logs,
    this.careEvents = const [],
    this.householdId = '',
  });

  /// Server id for the household. Opaque and globally unique.
  final String householdId;
  final String inviteCode;
  final bool isPro;
  final BillingPlan plan;
  final String memberId;
  final List<Member> members;
  final List<Pet> pets;
  final List<Medication> medications;
  final List<DoseRecord> logs;
  final List<CareEvent> careEvents;
}

class BatchOpResult {
  const BatchOpResult({
    required this.id,
    required this.status,
    this.log,
    this.message,
  });

  final String id;
  final String status;
  final DoseRecord? log;
  final String? message;
}

class BatchSyncResponse {
  const BatchSyncResponse({required this.results, this.household});

  final List<BatchOpResult> results;
  final HouseholdSnapshot? household;
}

/// This device's link to one household (stored privately on the phone).
class HouseholdSession {
  const HouseholdSession({required this.token, required this.snapshot});

  /// Private household link — not shown to the user.
  final String token;
  final HouseholdSnapshot snapshot;
}

enum HouseholdErrorKind {
  offline,
  unauthorized,
  notFound,
  conflict,
  invalid,
  server,
}

class HouseholdException implements Exception {
  const HouseholdException(
    this.message, {
    required this.kind,
    this.existing,
    this.status,
  });

  final String message;
  final HouseholdErrorKind kind;

  /// HTTP status when the server answered (e.g. 403 = needs household Pro).
  final int? status;

  /// For [HouseholdErrorKind.conflict]: the dose someone already logged.
  final DoseRecord? existing;

  @override
  String toString() => message;
}

/// Talks to the household API on Railway. No polling: fetch once, write on an action.
class HouseholdApi {
  HouseholdApi(Uri base, {Dio? dio, int retries = 2}) : _dio = dio ?? Dio() {
    _dio.options
      ..baseUrl = base.toString().replaceFirst(RegExp(r'/$'), '')
      ..connectTimeout = const Duration(seconds: 8)
      ..sendTimeout = const Duration(seconds: 10)
      ..receiveTimeout = const Duration(seconds: 12)
      ..contentType = Headers.jsonContentType
      ..responseType = ResponseType.json;
    _dio.interceptors.addAll([
      ApiAuthInterceptor(() => token),
      ApiRetryReadsInterceptor(_dio, retries),
      if (kDebugMode) ApiLogInterceptor(),
    ]);
  }

  final Dio _dio;

  /// Set once this device has joined or created a household.
  String? token;

  Future<HouseholdSession> createHousehold({
    required Member owner,
    required List<Member> caregivers,
    required List<Pet> pets,
    required List<Medication> medications,
    required List<DoseRecord> logs,
  }) async {
    final body = await _send('POST', '/v1/households', {
      'owner': {'id': owner.id, 'name': owner.isYou ? 'You' : owner.name},
      'caregivers': [
        for (final member in caregivers)
          {'id': member.id, 'name': member.name, 'role': member.role.name},
      ],
      'pets': [for (final pet in pets) pet.toJson()],
      'medications': [for (final item in medications) item.toJson()],
      'logs': [for (final log in logs) log.toJson()],
    });
    return _session(body);
  }

  Future<HouseholdSession> join({
    required String code,
    required String name,
  }) async {
    final body = await _send('POST', '/v1/join', {'code': code, 'name': name});
    return _session(body);
  }

  Future<HouseholdSnapshot> fetchHousehold() async {
    return _snapshot(await _send('GET', '/v1/household'));
  }

  Future<Pet> addPet(Pet pet) async {
    final body = await _send('POST', '/v1/pets', pet.toJson());
    return _pet(_map(body['pet']));
  }

  Future<Pet> updatePet(Pet pet) async {
    final body = await _send(
      'PATCH',
      '/v1/pets/${Uri.encodeComponent(pet.id)}',
      pet.toJson(),
    );
    return _pet(_map(body['pet']));
  }

  Future<Medication> addMedication(Medication medication) async {
    final body = await _send('POST', '/v1/medications', medication.toJson());
    return _medication(_map(body['medication']));
  }

  Future<void> removeMedication(String id) async {
    await _send('DELETE', '/v1/medications/${Uri.encodeComponent(id)}');
  }

  Future<Medication> refill(String medicationId) async {
    final body = await _send(
      'POST',
      '/v1/medications/${Uri.encodeComponent(medicationId)}/refill',
    );
    return _medication(_map(body['medication']));
  }

  /// Throws a conflict [HouseholdException] when the dose was already logged.
  Future<({DoseRecord log, Medication? medication})> logDose(
    DoseRecord record,
  ) async {
    final body = await _send('POST', '/v1/logs', record.toJson());
    final medication = body['medication'];
    return (
      log: _log(_map(body['log'])),
      medication: medication is Map<String, dynamic>
          ? _medication(medication)
          : null,
    );
  }

  Future<BillingPlan> setPlan(BillingPlan plan) async {
    final body = await _send('POST', '/v1/billing/plan', {'plan': plan.name});
    return _plan(body['plan']);
  }

  Future<({bool isPro, BillingPlan plan})> startTrial() async {
    final body = await _send('POST', '/v1/billing/trial');
    return (isPro: body['isPro'] == true, plan: _plan(body['plan']));
  }

  Future<BatchSyncResponse> syncBatch(List<SyncBatchOp> operations) async {
    final body = await _send('POST', '/v1/sync/batch', {
      'operations': [
        for (final op in operations)
          {'id': op.id, 'type': op.type, 'payload': op.payload},
      ],
    });
    final results = [
      for (final item
          in body['results'] is List ? body['results'] as List : const [])
        if (item is Map<String, dynamic>)
          BatchOpResult(
            id: '${item['id']}',
            status: '${item['status']}',
            log: item['log'] is Map<String, dynamic>
                ? _log(_map(item['log']))
                : null,
            message: item['message'] as String?,
          ),
    ];
    final house = body['household'];
    return BatchSyncResponse(
      results: results,
      household: house is Map<String, dynamic> ? _snapshot(house) : null,
    );
  }

  Future<CareEvent> addCareEvent(CareEvent event) async {
    final body = await _send('POST', '/v1/care-events', event.toJson());
    return CareEvent.fromJson(_map(body['careEvent']));
  }

  Future<void> removeCareEventRemote(String eventId) async {
    await _send('DELETE', '/v1/care-events/${Uri.encodeComponent(eventId)}');
  }

  Future<void> registerDevice({
    required String platform,
    required String token,
    required bool pushEnabled,
  }) async {
    await _send('POST', '/v1/devices/register', {
      'platform': platform,
      'token': token,
      'pushEnabled': pushEnabled,
    });
  }

  /// Creates a time-limited browser link for sitters (Pro households).
  Future<({String token, String url, DateTime expiresAt})> createSitterLink({
    String? label,
  }) async {
    final body = await _send('POST', '/v1/sitter-links', {
      if (label != null && label.isNotEmpty) 'label': label,
    });
    final rawToken = body['token'];
    if (rawToken is! String || rawToken.isEmpty) {
      throw const HouseholdException(
        'The sitter link response was incomplete.',
        kind: HouseholdErrorKind.invalid,
      );
    }
    final expiresRaw = body['expiresAt'];
    return (
      token: rawToken,
      url: '${body['url'] ?? ''}',
      expiresAt: expiresRaw is String
          ? DateTime.tryParse(expiresRaw) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  Future<void> leaveHousehold() async {
    await _send('POST', '/v1/members/leave');
  }

  Future<Map<String, dynamic>> exportHousehold() async {
    return _send('GET', '/v1/export');
  }

  Future<Map<String, dynamic>> _send(
    String method,
    String path, [
    Map<String, Object?>? data,
  ]) async {
    try {
      final response = await _dio.request<Object?>(
        path,
        data: data,
        options: Options(method: method),
      );
      return _map(response.data);
    } on DioException catch (error) {
      throw _translate(error);
    }
  }

  HouseholdException _translate(DioException error) {
    final status = error.response?.statusCode;
    final data = error.response?.data;
    final serverMessage = data is Map && data['error'] is String
        ? data['error'] as String
        : null;
    // The one log line for a failed call (success lines: ApiLogInterceptor).
    AppLog.event(
      'api.failed',
      apiCallFields(error.requestOptions, {
        'status': status ?? 0,
        'type': error.type.name,
        'error': ?serverMessage,
      }),
    );
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.connectionError:
      case DioExceptionType.cancel:
        return const HouseholdException(
          "Can't reach the household. Check your internet and try again.",
          kind: HouseholdErrorKind.offline,
        );
      // No response at all (socket closed, DNS) reads as offline too.
      case DioExceptionType.unknown when status == null:
        return const HouseholdException(
          "Can't reach the household. Check your internet and try again.",
          kind: HouseholdErrorKind.offline,
        );
      case DioExceptionType.badCertificate:
        return const HouseholdException(
          "Couldn't make a secure connection. Check your network and try again.",
          kind: HouseholdErrorKind.offline,
        );
      default:
        break;
    }
    return switch (status) {
      401 => HouseholdException(
        serverMessage ?? 'This phone is no longer in the household.',
        kind: HouseholdErrorKind.unauthorized,
        status: status,
      ),
      403 => HouseholdException(
        serverMessage ?? 'That needs Pawsitive Pro.',
        kind: HouseholdErrorKind.invalid,
        status: status,
      ),
      404 => HouseholdException(
        serverMessage ?? 'That was not found.',
        kind: HouseholdErrorKind.notFound,
        status: status,
      ),
      409 => HouseholdException(
        serverMessage ?? 'Someone already logged this dose.',
        kind: HouseholdErrorKind.conflict,
        status: status,
        existing: data is Map<String, dynamic> && data['log'] is Map
            ? _log(_map(data['log']))
            : null,
      ),
      400 || 413 => HouseholdException(
        serverMessage ?? 'Something in that form was not right.',
        kind: HouseholdErrorKind.invalid,
        status: status,
      ),
      429 => HouseholdException(
        serverMessage ?? 'Too many tries. Wait a minute and try again.',
        kind: HouseholdErrorKind.invalid,
        status: status,
      ),
      _ => const HouseholdException(
        'The household server had a problem. Try again in a moment.',
        kind: HouseholdErrorKind.server,
      ),
    };
  }
}

HouseholdSession _session(Map<String, dynamic> body) {
  final token = body['token'];
  if (token is! String || token.isEmpty) {
    throw const HouseholdException(
      'The household answer was not usable.',
      kind: HouseholdErrorKind.server,
    );
  }
  return HouseholdSession(token: token, snapshot: _snapshot(body));
}

HouseholdSnapshot _snapshot(Map<String, dynamic> body) {
  final house = body['household'] is Map<String, dynamic>
      ? body['household'] as Map<String, dynamic>
      : const <String, dynamic>{};
  return HouseholdSnapshot(
    householdId: '${house['id'] ?? ''}',
    inviteCode: '${house['inviteCode'] ?? ''}',
    isPro: house['isPro'] == true,
    plan: _plan(house['plan']),
    memberId: '${body['memberId'] ?? ''}',
    members: _list(body['members'], memberFromJson),
    pets: _list(body['pets'], _pet),
    medications: _list(body['medications'], _medication),
    logs: _list(body['logs'], _log),
    careEvents: _list(body['careEvents'], CareEvent.fromJson),
  );
}

Map<String, dynamic> _map(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value == null || value == '') return const {};
  throw const HouseholdException(
    'The household answer was not usable.',
    kind: HouseholdErrorKind.server,
  );
}

List<T> _list<T>(Object? value, T Function(Map<String, dynamic>) map) {
  if (value is! List) return [];
  return [
    for (final item in value)
      if (item is Map<String, dynamic>) map(item),
  ];
}

Member memberFromJson(Map<String, dynamic> json) {
  final name = '${json['name'] ?? ''}'.trim();
  final isYou = json['isYou'] == true;
  final role = _enum(MemberRole.values, json['role'], MemberRole.caregiver);
  return Member(
    id: '${json['id']}',
    name: isYou ? 'You' : (name.isEmpty ? 'Someone' : name),
    initials: isYou
        ? 'You'
        : (name.isEmpty ? '?' : name.characters.first.toUpperCase()),
    role: role,
    avatarTone: isYou
        ? AvatarTone.brand
        : (role == MemberRole.sitter ? AvatarTone.neutral : AvatarTone.soft),
    status: json['joined'] == false ? 'Not joined yet' : null,
    isYou: isYou,
    joined: json['joined'] != false,
  );
}

Pet petFromJson(Map<String, dynamic> json) => _pet(json);

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
    onTimePercent: 0,
    dailyMeds: 0,
  );
}

Medication medicationFromJson(Map<String, dynamic> json) => _medication(json);

Medication _medication(Map<String, dynamic> json) {
  final parts = [
    for (final item in json['parts'] is List ? json['parts'] as List : const [])
      ?_enumOrNull(DayPart.values, item),
  ];
  return Medication(
    id: '${json['id']}',
    petId: '${json['petId']}',
    name: '${json['name']}',
    amount: '${json['amount'] ?? ''}',
    parts: parts,
    supplyTotal: _int(json['supplyTotal']),
    dosesLeft: _int(json['dosesLeft']),
    startDay: '${json['startDay'] ?? ''}',
    endDay: '${json['endDay'] ?? ''}',
  );
}

DoseRecord doseRecordFromJson(Map<String, dynamic> json) => _log(json);

DoseRecord _log(Map<String, dynamic> json) {
  return DoseRecord(
    id: '${json['id']}',
    medicationId: '${json['medicationId']}',
    part: _enum(DayPart.values, json['part'], DayPart.morning),
    day: '${json['day']}',
    memberId: '${json['memberId']}',
    outcome: _enum(LogOutcome.values, json['outcome'], LogOutcome.given),
    amount: '${json['amount'] ?? ''}',
    timeLabel: '${json['timeLabel'] ?? ''}',
    note: json['note'] as String?,
  );
}

T _enum<T extends Enum>(List<T> values, Object? name, T fallback) =>
    _enumOrNull(values, name) ?? fallback;

T? _enumOrNull<T extends Enum>(List<T> values, Object? name) {
  for (final value in values) {
    if (value.name == name) return value;
  }
  return null;
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
