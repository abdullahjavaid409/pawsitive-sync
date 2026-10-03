import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:pawsitive_sync/data/household_api.dart';

typedef FakeReply = (int status, Object body);

/// In-memory HTTP adapter for household API tests.
class FakeHouseholdAdapter implements HttpClientAdapter {
  FakeHouseholdAdapter(this.replies);

  final List<FakeReply> replies;
  final requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    if (replies.isEmpty) {
      return ResponseBody.fromString(
        jsonEncode({'error': 'no more replies'}),
        500,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    }
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

HouseholdApi fakeHouseholdApi(FakeHouseholdAdapter adapter, {String? token}) {
  final dio = Dio()..httpClientAdapter = adapter;
  final api = HouseholdApi(Uri.parse('https://example.test'), dio: dio);
  if (token != null) api.token = token;
  return api;
}

Map<String, Object?> connectHouseholdBody({
  String inviteCode = 'ABC234',
  bool isPro = true,
  String memberId = 'you',
  List<Map<String, Object?>> logs = const [],
  String householdId = 'hh_test',
}) {
  return {
    'token': 'house-token',
    'household': {
      'id': householdId,
      'inviteCode': inviteCode,
      'isPro': isPro,
      'plan': 'yearly',
    },
    'memberId': memberId,
    'members': [
      {'id': 'you', 'name': 'You', 'role': 'owner', 'isYou': true},
      {'id': 'dan', 'name': 'Dan', 'role': 'caregiver', 'joined': true},
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
        'parts': ['morning'],
        'supplyTotal': 30,
        'dosesLeft': 30,
        'startDay': '2026-01-01',
      },
    ],
    'logs': logs,
    'careEvents': [],
  };
}
