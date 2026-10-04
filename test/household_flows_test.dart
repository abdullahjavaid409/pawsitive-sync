import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pawsitive_sync/core/logging/app_log.dart';
import 'package:pawsitive_sync/data/care_repository.dart';
import 'package:pawsitive_sync/data/household_api.dart';
import 'package:pawsitive_sync/data/sync_engine.dart';
import 'package:pawsitive_sync/data/sync_outbox.dart';
import 'package:pawsitive_sync/domain/models.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_household_api.dart';
import 'test_log_helpers.dart';

/// Answers by "METHOD /path". `offline` makes every call fail like no network.
class _RouteAdapter implements HttpClientAdapter {
  _RouteAdapter(this.routes);

  final Map<String, FakeReply Function(Object? body)> routes;
  final calls = <(String, Object?)>[];
  bool offline = false;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final key = '${options.method} ${options.path}';
    calls.add((key, options.data));
    if (offline) {
      throw DioException.connectionError(
        requestOptions: options,
        reason: 'offline (test)',
      );
    }
    final handler = routes[key];
    final (status, body) = handler == null
        ? (404, {'error': 'Not found'})
        : handler(options.data);
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

  List<Object?> bodiesFor(String key) => [
    for (final call in calls)
      if (call.$1 == key) call.$2,
  ];
}

void main() {
  late _RouteAdapter adapter;
  late SyncOutbox outbox;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppLog.enableTestCapture();
    outbox = SyncOutbox();
  });

  tearDown(AppLog.disableTestCapture);

  Future<CareRepository> connectedCare(
    Map<String, FakeReply Function(Object? body)> extra,
  ) async {
    adapter = _RouteAdapter({
      'POST /v1/households': (_) => (201, connectHouseholdBody()),
      'POST /v1/devices/register': (_) => (200, {'ok': true}),
      ...extra,
    });
    final care = CareRepository(
      api: HouseholdApi(
        Uri.parse('https://example.test'),
        dio: Dio()..httpClientAdapter = adapter,
      ),
      syncEngine: SyncEngine(outbox: outbox),
      clock: () => DateTime(2026, 10, 3, 14),
    );
    await care.addPet(name: 'Milo', species: Species.cat);
    expect(await care.connect(), isNull);
    expect(care.isConnected, isTrue);
    AppLog.testRecords.clear();
    return care;
  }

  group('Offline dose while shared', () {
    test('is kept locally, queued, and flushed with the same id', () async {
      final serverLogs = <Map<String, Object?>>[];
      final care = await connectedCare({
        'POST /v1/sync/batch': (body) {
          final ops = (body as Map)['operations'] as List;
          final op = ops.single as Map;
          final payload = op['payload'] as Map;
          serverLogs.add(Map<String, Object?>.from(payload));
          return (
            200,
            {
              'results': [
                {'id': op['id'], 'status': 'ok', 'log': payload},
              ],
              'household': connectHouseholdBody(
                logs: [Map<String, Object?>.from(payload)],
              ),
            },
          );
        },
        'GET /v1/household': (_) =>
            (200, connectHouseholdBody(logs: serverLogs)),
      });
      adapter.offline = true;

      final ok = await care.logDose(
        doseId: CareRepository.doseIdFor('insulin', DayPart.morning),
        memberId: 'you',
        amount: '2 u',
        timeLabel: '2:00 PM',
      );

      expect(ok, isTrue, reason: 'dose logging must work with no network');
      expect(care.lastError, isNull);
      final local = care.logs.single;
      expectLogged(
        'dose.log.completed',
        fields: {'offline': true, 'queued': true},
      );
      final queued = await outbox.read();
      expect(queued.single.type, 'logDose');
      expect(queued.single.payload['id'], local.id);

      adapter.offline = false;
      await care.sync(force: true);

      final sent = adapter.bodiesFor('POST /v1/sync/batch').single as Map;
      final sentOp = (sent['operations'] as List).single as Map;
      expect((sentOp['payload'] as Map)['id'], local.id);
      expect(await outbox.read(), isEmpty);
      expect(care.logs.map((log) => log.id), contains(local.id));
      expect(care.lastError, isNull);
      expectLogged('sync.batch.completed');
    });

    test('a partner dose logged first wins and the person is told', () async {
      const partnerLog = {
        'id': 'log-partner',
        'medicationId': 'insulin',
        'part': 'morning',
        'day': '2026-10-03',
        'memberId': 'dan',
        'outcome': 'given',
        'amount': '2 u',
        'timeLabel': '8:05 AM',
      };
      final care = await connectedCare({
        'POST /v1/sync/batch': (body) {
          final op = ((body as Map)['operations'] as List).single as Map;
          return (
            200,
            {
              'results': [
                {'id': op['id'], 'status': 'conflict', 'log': partnerLog},
              ],
              'household': connectHouseholdBody(logs: [partnerLog]),
            },
          );
        },
        'GET /v1/household': (_) =>
            (200, connectHouseholdBody(logs: [partnerLog])),
      });
      adapter.offline = true;
      await care.logDose(
        doseId: CareRepository.doseIdFor('insulin', DayPart.morning),
        memberId: 'you',
        amount: '2 u',
        timeLabel: '2:00 PM',
      );
      adapter.offline = false;
      await care.sync(force: true);

      expect(care.logs.single.id, 'log-partner');
      expect(care.lastError, contains('already logged'));
      expectLogged('sync.batch.conflict', fields: {'logId': 'log-partner'});
    });

    test(
      'our own dose already saved is not reported as a double dose',
      () async {
        final care = await connectedCare({
          'POST /v1/sync/batch': (body) {
            final op = ((body as Map)['operations'] as List).single as Map;
            final payload = Map<String, Object?>.from(op['payload'] as Map);
            return (
              200,
              {
                'results': [
                  {'id': op['id'], 'status': 'conflict', 'log': payload},
                ],
                'household': connectHouseholdBody(logs: [payload]),
              },
            );
          },
          'GET /v1/household': (_) => (200, connectHouseholdBody()),
        });
        adapter.offline = true;
        await care.logDose(
          doseId: CareRepository.doseIdFor('insulin', DayPart.morning),
          memberId: 'you',
          amount: '2 u',
          timeLabel: '2:00 PM',
        );
        adapter.offline = false;
        await care.sync(force: true);

        expect(care.lastError, isNull);
        expectNotLogged('sync.batch.conflict');
      },
    );
  });

  group('Expired household link (401)', () {
    test('sync drops the link but keeps every pet and dose', () async {
      final care = await connectedCare({
        'GET /v1/household': (_) =>
            (401, {'error': 'Sign in again to reach this household.'}),
      });
      final pets = care.pets.length;

      await care.sync(force: true);

      expect(care.isConnected, isFalse);
      expect(care.pets.length, pets);
      expect(care.syncError, contains('join again'));
      expectLogged('household.sync_failed', fields: {'kind': 'unauthorized'});
      expectLogged(
        'household.session_expired',
        fields: {'reason': 'sync_unauthorized'},
      );

      // Logging still works on the phone after the link is gone.
      final ok = await care.logDose(
        doseId: CareRepository.doseIdFor('insulin', DayPart.morning),
        memberId: 'you',
        amount: '',
        timeLabel: '2:00 PM',
      );
      expect(ok, isTrue);
    });
  });

  group('Leave household', () {
    test('tells the server, then clears this phone', () async {
      final care = await connectedCare({
        'POST /v1/members/leave': (_) => (200, {'left': true}),
      });

      expect(await care.leaveHousehold(), isNull);

      expect(adapter.bodiesFor('POST /v1/members/leave'), hasLength(1));
      expect(care.isConnected, isFalse);
      expect(care.pets, isEmpty);
      expectLogged('household.left', fields: {'wasConnected': true});
      expectLogged('household.reset');
    });

    test('offline leave keeps the household and explains why', () async {
      final care = await connectedCare({});
      adapter.offline = true;

      final error = await care.leaveHousehold();

      expect(error, contains('internet'));
      expect(care.isConnected, isTrue);
      expect(care.pets, isNotEmpty);
      expectLogged('household.leave_failed', fields: {'kind': 'offline'});
      expectNotLogged('household.reset');
    });

    test('already removed on the server (401) still clears locally', () async {
      final care = await connectedCare({
        'POST /v1/members/leave': (_) => (401, {'error': 'Sign in again.'}),
      });

      expect(await care.leaveHousehold(), isNull);
      expect(care.isConnected, isFalse);
      expectLogged('household.left');
    });

    test('rejoin with the code after leaving', () async {
      final care = await connectedCare({
        'POST /v1/members/leave': (_) => (200, {'left': true}),
        'POST /v1/join': (_) => (
          201,
          connectHouseholdBody(memberId: 'member-new')
            ..['members'] = [
              {'id': 'you', 'name': 'Owner', 'role': 'owner'},
              {
                'id': 'member-new',
                'name': 'Dan',
                'role': 'caregiver',
                'isYou': true,
              },
            ],
        ),
      });
      expect(await care.leaveHousehold(), isNull);

      expect(await care.join(code: 'abc-234', name: 'Dan'), isNull);

      final body = adapter.bodiesFor('POST /v1/join').single as Map;
      expect(body['code'], 'ABC234');
      expect(care.isConnected, isTrue);
      expect(care.memberId, 'member-new');
      expect(care.pets.single.id, 'miso');
      expectLogged('household.joined');
    });
  });

  group('Sitter browser link', () {
    test('403 from a Free household shows the server reason', () async {
      final care = await connectedCare({
        'POST /v1/sitter-links': (_) =>
            (403, {'error': 'Browser sitter links need Pawsitive Pro.'}),
      });
      // This phone believes it is Pro (store), but the household is not yet.
      care.debugStorePro = true;

      expect(await care.ensureSitterWebLink(force: true), isNull);

      expect(care.lastError, 'Browser sitter links need Pawsitive Pro.');
      expectLogged('sitter.link_failed', fields: {'kind': 'invalid'});
    });
  });
}
