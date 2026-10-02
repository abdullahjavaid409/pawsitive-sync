import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pawsitive_sync/data/household_api.dart';
import 'package:pawsitive_sync/domain/models.dart';

typedef _Reply = (int status, Object body);

class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.replies);

  final List<_Reply> replies;
  final requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final (status, body) = replies.removeAt(0);
    return ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

HouseholdApi _api(_FakeAdapter adapter) {
  final dio = Dio()..httpClientAdapter = adapter;
  return HouseholdApi(Uri.parse('https://example.test'), dio: dio)
    ..token = 'secret';
}

const _record = DoseRecord(
  id: 'log1',
  medicationId: 'insulin',
  part: DayPart.morning,
  day: '2026-10-02',
  memberId: 'you',
  outcome: LogOutcome.given,
  amount: '2 u',
  timeLabel: '8:02 AM',
);

void main() {
  test('updates a pet with PATCH', () async {
    final adapter = _FakeAdapter([
      (
        200,
        {
          'pet': {
            'id': 'miso',
            'name': 'Miso Jr',
            'species': 'cat',
            'ageYears': 13,
            'weightKg': '5.2',
            'conditions': ['Diabetes'],
          },
        },
      ),
    ]);
    final api = _api(adapter);
    final pet = await api.updatePet(
      const Pet(
        id: 'miso',
        name: 'Miso Jr',
        species: Species.cat,
        ageYears: 13,
        breed: '',
        sex: '',
        conditions: ['Diabetes'],
        weightKg: 5.2,
        onTimePercent: 0,
        dailyMeds: 0,
      ),
    );
    expect(pet.name, 'Miso Jr');
    expect(adapter.requests.single.method, 'PATCH');
    expect(adapter.requests.single.path, '/v1/pets/miso');
  });

  test('reads the household and sends the sign-in token', () async {
    final adapter = _FakeAdapter([
      (
        200,
        {
          'household': {'inviteCode': 'ABC234', 'isPro': true, 'plan': 'monthly'},
          'memberId': 'you',
          'members': [
            {'id': 'you', 'name': 'Sara', 'role': 'owner', 'isYou': true},
            {'id': 'dan', 'name': 'Dan', 'role': 'caregiver', 'joined': false},
          ],
          'pets': [
            {
              'id': 'miso',
              'name': 'Miso',
              'species': 'cat',
              'ageYears': 12,
              'weightKg': '4.6',
              'conditions': ['Diabetes'],
            },
          ],
          'medications': [
            {
              'id': 'insulin',
              'petId': 'miso',
              'name': 'Insulin',
              'amount': '2 u',
              'parts': ['morning', 'bedtime', 'evening'],
              'supplyTotal': 0,
              'dosesLeft': 0,
            },
          ],
          'logs': [_record.toJson()],
        },
      ),
    ]);

    final house = await _api(adapter).fetchHousehold();

    expect(adapter.requests.single.path, '/v1/household');
    expect(
      adapter.requests.single.headers['Authorization'],
      'Bearer secret',
    );
    expect(house.inviteCode, 'ABC234');
    expect(house.isPro, isTrue);
    expect(house.plan, BillingPlan.monthly);
    expect(house.members.first.isYou, isTrue);
    expect(house.members.last.joined, isFalse);
    expect(house.pets.single.weightKg, 4.6);
    expect(house.medications.single.parts, [DayPart.morning, DayPart.evening]);
    expect(house.logs.single.medicationId, 'insulin');
  });

  test('a second log of the same dose says who already gave it', () async {
    final adapter = _FakeAdapter([
      (
        409,
        {
          'error': 'Someone already logged this dose.',
          'log': {..._record.toJson(), 'memberId': 'dan'},
        },
      ),
    ]);

    await expectLater(
      _api(adapter).logDose(_record),
      throwsA(
        isA<HouseholdException>()
            .having((e) => e.kind, 'kind', HouseholdErrorKind.conflict)
            .having((e) => e.existing?.memberId, 'existing', 'dan'),
      ),
    );
  });

  test('reads retry after a gateway error', () async {
    final adapter = _FakeAdapter([
      (503, {'error': 'busy'}),
      (200, {'household': {'inviteCode': 'ABC234'}}),
    ]);

    final house = await _api(adapter).fetchHousehold();

    expect(adapter.requests, hasLength(2));
    expect(house.inviteCode, 'ABC234');
  });

  test('writes are never retried', () async {
    final adapter = _FakeAdapter([
      (503, {'error': 'busy'}),
    ]);

    await expectLater(
      _api(adapter).logDose(_record),
      throwsA(
        isA<HouseholdException>().having(
          (e) => e.kind,
          'kind',
          HouseholdErrorKind.server,
        ),
      ),
    );
    expect(adapter.requests, hasLength(1));
  });

  test('a wrong invite code reads as not found', () async {
    final adapter = _FakeAdapter([
      (404, {'error': 'That invite code was not found. Check it and try again.'}),
    ]);

    await expectLater(
      _api(adapter).join(code: 'ZZZZZZ', name: 'Dan'),
      throwsA(
        isA<HouseholdException>()
            .having((e) => e.kind, 'kind', HouseholdErrorKind.notFound)
            .having((e) => e.message, 'message', contains('not found')),
      ),
    );
  });
}
