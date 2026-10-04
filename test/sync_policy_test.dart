import 'package:flutter_test/flutter_test.dart';
import 'package:pawsitive_sync/core/logging/app_log.dart';
import 'package:pawsitive_sync/data/care_repository.dart';
import 'package:pawsitive_sync/data/household_store.dart';
import 'package:pawsitive_sync/data/sync_outbox.dart';
import 'package:pawsitive_sync/data/sync_policy.dart';
import 'package:pawsitive_sync/domain/models.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_household_api.dart';
import 'test_log_helpers.dart';

void main() {
  final now = DateTime(2026, 10, 4, 12);

  group('SyncPolicy.decide', () {
    // (description, args, expected sync, expected reason)
    final cases = <(String, SyncDecision Function(), bool, SyncReason)>[
      ('fresh: synced 5 min ago, nothing pending',
          () => SyncPolicy.decide(now: now, lastSuccess: now.subtract(const Duration(minutes: 5))),
          false, SyncReason.fresh),
      ('just under 15 min is still fresh',
          () => SyncPolicy.decide(now: now, lastSuccess: now.subtract(const Duration(minutes: 14, seconds: 59))),
          false, SyncReason.fresh),
      ('15 min or older is stale',
          () => SyncPolicy.decide(now: now, lastSuccess: now.subtract(SyncPolicy.maxAge)),
          true, SyncReason.stale),
      ('never synced on this install',
          () => SyncPolicy.decide(now: now, lastSuccess: null),
          true, SyncReason.never),
      ('outbox has changes, even when fresh',
          () => SyncPolicy.decide(now: now, lastSuccess: now, hasPending: true),
          true, SyncReason.pending),
      ('push says something changed',
          () => SyncPolicy.decide(now: now, lastSuccess: now, pushSaysChanged: true),
          true, SyncReason.push),
      ('pull to refresh',
          () => SyncPolicy.decide(now: now, lastSuccess: now, userRequested: true),
          true, SyncReason.user),
      ('right after connect/join',
          () => SyncPolicy.decide(now: now, lastSuccess: now, justConnected: true),
          true, SyncReason.connected),
      ('offline 10 s ago: back off (pending waits too)',
          () => SyncPolicy.decide(
                now: now,
                lastSuccess: null,
                hasPending: true,
                offlineFailures: 1,
                lastFailure: now.subtract(const Duration(seconds: 10)),
              ),
          false, SyncReason.noNetwork),
      ('offline backoff over: try again',
          () => SyncPolicy.decide(
                now: now,
                lastSuccess: null,
                offlineFailures: 1,
                lastFailure: now.subtract(const Duration(seconds: 31)),
              ),
          true, SyncReason.never),
      ('pull to refresh ignores the backoff',
          () => SyncPolicy.decide(
                now: now,
                lastSuccess: null,
                userRequested: true,
                offlineFailures: 5,
                lastFailure: now,
              ),
          true, SyncReason.user),
      ('clock moved back: last sync "in the future" is not trusted',
          () => SyncPolicy.decide(now: now, lastSuccess: now.add(const Duration(hours: 3))),
          true, SyncReason.never),
      ('a few seconds of clock correction is still fresh',
          () => SyncPolicy.decide(now: now, lastSuccess: now.add(const Duration(seconds: 20))),
          false, SyncReason.fresh),
      ('failure time in the future (clock moved): no backoff',
          () => SyncPolicy.decide(
                now: now,
                lastSuccess: now.subtract(const Duration(hours: 1)),
                offlineFailures: 3,
                lastFailure: now.add(const Duration(minutes: 5)),
              ),
          true, SyncReason.stale),
    ];
    for (final (name, decide, sync, reason) in cases) {
      test(name, () {
        final d = decide();
        expect(d.sync, sync);
        expect(d.reason, reason);
      });
    }

    test('backoff grows and caps at 10 minutes', () {
      expect(SyncPolicy.backoff(0), Duration.zero);
      expect(SyncPolicy.backoff(1), const Duration(seconds: 30));
      expect(SyncPolicy.backoff(2), const Duration(minutes: 1));
      expect(SyncPolicy.backoff(4), const Duration(minutes: 4));
      expect(SyncPolicy.backoff(20), const Duration(minutes: 10));
      expect(
        const SyncDecision(false, SyncReason.noNetwork).reasonName,
        'no_network',
      );
    });
  });

  group('API calls per normal open', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      AppLog.enableTestCapture();
    });
    tearDown(AppLog.disableTestCapture);

    /// Connects once, then "relaunches" [minutesLater] minutes after.
    Future<(CareRepository, FakeHouseholdAdapter)> relaunch(
      int minutesLater, {
      List<FakeReply> replies = const [],
    }) async {
      var clock = now;
      final first = CareRepository(
        api: fakeHouseholdApi(
          FakeHouseholdAdapter([
            (201, connectHouseholdBody()),
            (200, {'ok': true, 'stored': true, 'delivery': true}),
          ]),
        ),
        store: HouseholdStore(),
        clock: () => clock,
      );
      await first.addPet(name: 'Miso', species: Species.cat);
      expect(await first.connect(), isNull);
      await first.flushPersist();
      await Future<void>.delayed(const Duration(milliseconds: 30));
      clock = now.add(Duration(minutes: minutesLater));
      final adapter = FakeHouseholdAdapter([...replies]);
      final care = CareRepository(
        api: fakeHouseholdApi(adapter),
        store: HouseholdStore(),
        clock: () => clock,
      );
      await care.restore();
      expect(care.isConnected, isTrue);
      AppLog.testRecords.clear();
      return (care, adapter);
    }

    test('open 5 min after the last sync: 0 calls (was 1)', () async {
      final (care, adapter) = await relaunch(5);
      await care.syncIfStale(source: 'launch');
      expect(adapter.requests, isEmpty);
      expectLogged(
        'household.sync_skipped',
        fields: {'reason': 'fresh', 'source': 'launch', 'secondsAgo': 300},
      );
      // Resume a minute later: still 0 (the old 45 s throttle called again).
      await care.syncIfStale(source: 'resume');
      expect(adapter.requests, isEmpty);
    });

    test('open 20 min later: exactly one fetch, reason=stale', () async {
      final (care, adapter) = await relaunch(
        20,
        replies: [(200, connectHouseholdBody())],
      );
      await care.syncIfStale(source: 'launch');
      expect(
        [for (final r in adapter.requests) '${r.method} ${r.path}'],
        ['GET /v1/household'],
      );
      expectLogged('household.synced', fields: {'reason': 'stale'});
      // Synced now: the next resume is local again.
      await care.syncIfStale(source: 'resume');
      expect(adapter.requests, hasLength(1));
    });

    test('pending outbox change syncs even when fresh', () async {
      final (care, adapter) = await relaunch(
        2,
        replies: [
          (200, {'results': <Object>[], 'household': null}),
          (200, connectHouseholdBody()),
        ],
      );
      await SyncOutbox().enqueue(
        const SyncBatchOp(id: 'op-1', type: 'refill', payload: {'id': 'x'}),
      );
      await care.syncIfStale(source: 'resume');
      expect(adapter.requests, isNotEmpty);
      expect(adapter.requests.last.path, '/v1/household');
    });

    test('pull to refresh always asks the server', () async {
      final (care, adapter) = await relaunch(
        1,
        replies: [(200, connectHouseholdBody())],
      );
      await care.sync(force: true, source: 'pull_refresh');
      expect(adapter.requests.single.path, '/v1/household');
    });

    test('offline: one try, then backoff logs no_network (no retry storm)', () async {
      // GETs get built-in retries (ApiRetryReadsInterceptor): all fail.
      final (care, adapter) = await relaunch(
        30,
        replies: [for (var i = 0; i < 4; i++) (0, 'offline')],
      );
      await care.syncIfStale(source: 'launch');
      final tried = adapter.requests.length;
      expect(tried, inInclusiveRange(1, 3), reason: 'one sync attempt');
      expectLogged('household.sync_failed', fields: {'kind': 'offline'});
      AppLog.testRecords.clear();
      await care.syncIfStale(source: 'resume');
      expect(adapter.requests, hasLength(tried), reason: 'backing off');
      expectLogged('household.sync_skipped', fields: {'reason': 'no_network'});
    });
  });
}
