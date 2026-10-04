import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pawsitive_sync/core/logging/app_log.dart';
import 'package:pawsitive_sync/data/care_repository.dart';
import 'package:pawsitive_sync/data/dose_reminders.dart';
import 'package:pawsitive_sync/data/household_api.dart';
import 'package:pawsitive_sync/data/push_service.dart';
import 'package:pawsitive_sync/data/reminders/reminder_plan.dart';
import 'package:pawsitive_sync/data/sync_outbox.dart';
import 'package:pawsitive_sync/domain/models.dart';
import 'package:pawsitive_sync/ui/household/household_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_household_api.dart';
import 'fake_push_platform.dart';
import 'fake_reminder_platform.dart';
import 'test_log_helpers.dart';

/// A reply, or `timeout` to simulate a slow link that never answers.
typedef Step = (int status, Object body);
const timeout = (0, 'timeout');

/// Fake adapter that can also time out (the outcome on the server unknown).
class StepAdapter implements HttpClientAdapter {
  StepAdapter(this.steps);

  final List<Step> steps;
  final requests = <RequestOptions>[];

  List<String> get paths => [for (final r in requests) '${r.method} ${r.path}'];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final (status, body) = steps.isEmpty
        ? (500, {'error': 'no more replies'})
        : steps.removeAt(0);
    if (body == 'timeout') {
      throw DioException(
        requestOptions: options,
        type: DioExceptionType.receiveTimeout,
      );
    }
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

/// A server snapshot where this phone is [me] with [role].
Map<String, Object?> snapshot({
  String me = 'you',
  MemberRole role = MemberRole.owner,
  String inviteCode = 'ABC234',
  String? inviteExpiresAt,
  bool danPays = false,
}) {
  final base = connectHouseholdBody(memberId: me, inviteCode: inviteCode);
  return {
    ...base,
    'household': {
      ...(base['household']! as Map<String, Object?>),
      'inviteExpiresAt': ?inviteExpiresAt,
    },
    'role': role.name,
    'members': [
      {
        'id': 'you',
        'name': 'Sam',
        'role': 'owner',
        if (me == 'you') 'isYou': true,
      },
      {
        'id': 'dan',
        'name': 'Dan',
        'role': me == 'dan' ? role.name : 'caregiver',
        if (me == 'dan') 'isYou': true,
        if (danPays) 'paysForPro': true,
      },
    ],
  };
}

final _clock = DateTime(2026, 10, 4, 7, 30);

/// A connected phone. Replies: the join/create answer, the push
/// registration, then [more].
Future<(CareRepository, StepAdapter)> connected({
  String me = 'you',
  MemberRole role = MemberRole.owner,
  List<Step> more = const [],
  String? inviteExpiresAt,
  bool danPays = false,
}) async {
  final adapter = StepAdapter([
    (
      201,
      snapshot(
        me: me,
        role: role,
        inviteExpiresAt: inviteExpiresAt,
        danPays: danPays,
      ),
    ),
    (200, {'ok': true, 'stored': true, 'delivery': true}),
    ...more,
  ]);
  final dio = Dio()..httpClientAdapter = adapter;
  final api = HouseholdApi(Uri.parse('https://example.test'), dio: dio);
  final care = CareRepository(api: api, clock: () => _clock);
  final error = await care.join(code: 'ABC234', name: 'Dan');
  expect(error, isNull);
  // Push registration runs in the background after join; let it land so
  // the queued replies stay in order.
  await Future<void>.delayed(const Duration(milliseconds: 30));
  return (care, adapter);
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppLog.enableTestCapture();
  });

  group('roles on the phone', () {
    test(
      'caregiver: stopping a medicine is refused before any request',
      () async {
        final (care, adapter) = await connected(
          me: 'dan',
          role: MemberRole.caregiver,
        );
        expect(care.myRole, MemberRole.caregiver);
        expect(care.canEditCare, isTrue);
        expect(care.canArchive, isFalse);
        final sent = adapter.requests.length;
        expect(await care.removeMedication('insulin'), isFalse);
        expect(care.lastError, CareRepository.ownerOnlyMessage);
        expect(adapter.requests.length, sent, reason: 'no request');
        expect(
          care.medicationById('insulin'),
          isNotNull,
          reason: 'nothing hidden',
        );
        expectLogged(
          'medication.remove.blocked',
          fields: {'role': 'caregiver'},
        );
      },
    );

    test(
      'sitter: logs doses, but can’t add pets, refill or add medicines',
      () async {
        final (care, adapter) = await connected(
          me: 'dan',
          role: MemberRole.sitter,
          more: [
            (
              201,
              {
                'log': {
                  'id': 'log-1',
                  'medicationId': 'insulin',
                  'part': 'morning',
                  'day': '2026-10-04',
                  'memberId': 'dan',
                  'outcome': 'given',
                  'timeLabel': '7:30 AM',
                },
              },
            ),
          ],
        );
        expect(care.canEditCare, isFalse);
        expect(await care.addPet(name: 'Pip', species: Species.dog), isNull);
        expect(care.lastError, CareRepository.sitterOnlyMessage);
        expect(await care.refill('insulin'), isFalse);
        expect(
          await care.addMedication(
            petId: 'miso',
            name: 'Gaba',
            amount: '',
            parts: [DayPart.evening],
          ),
          isFalse,
        );
        expect(
          await care.logDose(
            doseId: 'insulin.morning',
            memberId: 'dan',
            amount: '2 u',
            timeLabel: '7:30 AM',
          ),
          isTrue,
        );
        expect(
          adapter.paths.where((p) => p.startsWith('POST /v1/logs')),
          hasLength(1),
        );
        expect(
          adapter.paths.where(
            (p) => p.contains('/pets') || p.contains('refill'),
          ),
          isEmpty,
        );
      },
    );

    test(
      'role changed on another phone: 403 explains and pulls the new role',
      () async {
        final (care, adapter) = await connected(
          me: 'dan',
          role: MemberRole.caregiver,
          more: [
            (
              403,
              {
                'error': 'Only the household owner can do that.',
                'code': 'role_forbidden',
              },
            ),
            (200, snapshot(me: 'dan', role: MemberRole.sitter)),
          ],
        );
        expect(await care.refill('insulin'), isFalse);
        expect(care.lastError, 'Only the household owner can do that.');
        expect(
          care.isConnected,
          isTrue,
          reason: 'a role change is not a sign-out',
        );
        // The background refresh lands.
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(adapter.paths.last, 'GET /v1/household');
        expect(care.myRole, MemberRole.sitter);
        expect(care.canEditCare, isFalse);
        expectLogged('household.role_forbidden');
      },
    );

    test(
      'a queued change the role no longer allows is dropped with a message',
      () async {
        final (care, adapter) = await connected(
          me: 'dan',
          role: MemberRole.caregiver,
          more: [
            timeout, // the refill call: queued for later
            (
              200,
              {
                'results': [
                  {
                    'id': 'x',
                    'status': 'error',
                    'message': 'Sitters can view and log doses only. Ask the owner for more access.',
                    'code': 'role_forbidden',
                  },
                ],
                'household': snapshot(me: 'dan', role: MemberRole.sitter),
              },
            ),
          ],
        );
        expect(await care.refill('insulin'), isTrue, reason: 'kept offline');
        final pending = await SyncOutbox().read();
        expect(pending, hasLength(1));
        // Replace the op id the server echoes with the real one.
        final result = (adapter.steps.first.$2 as Map)['results'] as List;
        (result.first as Map)['id'] = pending.single.id;
        await care.sync(force: true);
        expect(
          care.lastError,
          startsWith('Sitters can view and log doses only'),
        );
        expect(care.myRole, MemberRole.sitter);
        expect(await SyncOutbox().read(), isEmpty, reason: 'never retried');
        expectLogged('sync.batch.role_rejected');
      },
    );

    test(
      'removed by the owner: friendly message, data kept, link dropped',
      () async {
        final (care, _) = await connected(
          me: 'dan',
          role: MemberRole.caregiver,
          more: [
            (
              401,
              {
                'error': 'The household owner removed you from this household.',
                'code': 'member_removed',
              },
            ),
          ],
        );
        await care.sync(force: true);
        expect(care.isConnected, isFalse);
        expect(care.syncError, CareRepository.memberRemovedMessage);
        expect(care.pets, isNotEmpty);
        expectLogged('household.removed_by_owner');
        expectNotLogged('household.deleted_by_owner');
      },
    );

    test(
      'caregiver: plan choice stays on the phone (no household billing call)',
      () async {
        final (care, adapter) = await connected(
          me: 'dan',
          role: MemberRole.caregiver,
        );
        final sent = adapter.requests.length;
        await care.setPlan(BillingPlan.monthly);
        expect(care.plan, BillingPlan.monthly);
        expect(adapter.requests.length, sent);
      },
    );
  });

  group('owner household management', () {
    test('invite expiry is shown in days; rotate swaps the code once per tap burst', () async {
      final (care, adapter) = await connected(
        inviteExpiresAt: '2026-10-09T07:30:00.000Z',
        more: [
          (
            200,
            {
              'inviteCode': 'NEW777',
              'inviteExpiresAt': '2026-10-11T07:30:00.000Z',
            },
          ),
        ],
      );
      expect(care.inviteDaysLeft, inInclusiveRange(4, 6));
      expect(care.inviteExpired, isFalse);
      final results = await Future.wait([
        care.rotateInvite(),
        care.rotateInvite(),
      ]);
      expect(results, [null, null]);
      expect(
        adapter.paths.where((p) => p == 'POST /v1/invite/rotate'),
        hasLength(1),
      );
      expect(care.inviteCode, 'NEW777');
      expect(care.inviteExpiresAt, DateTime.parse('2026-10-11T07:30:00.000Z'));
    });

    test(
      'rotate on a timeout keeps the old code and says it is unconfirmed',
      () async {
        final (care, _) = await connected(more: [timeout]);
        final error = await care.rotateInvite();
        expect(error, contains("Couldn't confirm"));
        expect(care.inviteCode, 'ABC234');
      },
    );

    test('an expired code reads as expired', () async {
      final (care, _) = await connected(
        inviteExpiresAt: '2026-10-01T00:00:00.000Z',
      );
      expect(care.inviteExpired, isTrue);
      expect(care.inviteDaysLeft, 0);
    });

    test('non-owners never call owner endpoints', () async {
      final (care, adapter) = await connected(
        me: 'dan',
        role: MemberRole.caregiver,
      );
      final sent = adapter.requests.length;
      expect(await care.rotateInvite(), CareRepository.ownerOnlyMessage);
      expect(await care.loadSitterLinks(), CareRepository.ownerOnlyMessage);
      expect(await care.removeMember('you'), CareRepository.ownerOnlyMessage);
      expect(adapter.requests.length, sent);
      expect(care.inviteCode, 'ABC234');
    });

    test(
      'sitter links: list, revoke (twice = once), cached link forgotten',
      () async {
        final (care, adapter) = await connected(
          more: [
            (
              200,
              {
                'links': [
                  {
                    'id': 'slink-a',
                    'label': 'Weekend',
                    'expiresAt': '2026-11-01T00:00:00.000Z',
                    'createdAt': '2026-10-01T00:00:00.000Z',
                    'lastUsedAt': '2026-10-03T09:00:00.000Z',
                  },
                  {
                    'id': 'slink-b',
                    'label': 'Neighbour',
                    'expiresAt': '2026-11-02T00:00:00.000Z',
                  },
                ],
              },
            ),
            (200, {'ok': true, 'revoked': true}),
          ],
        );
        expect(await care.loadSitterLinks(), isNull);
        expect(care.sitterLinks.map((l) => l.label), ['Weekend', 'Neighbour']);
        expect(care.sitterLinks.first.lastUsedAt, isNotNull);
        final both = await Future.wait([
          care.revokeSitterLink('slink-a'),
          care.revokeSitterLink('slink-a'),
        ]);
        expect(both, [null, null]);
        expect(
          adapter.paths.where((p) => p == 'DELETE /v1/sitter-links/slink-a'),
          hasLength(1),
        );
        expect(care.sitterLinks.map((l) => l.id), ['slink-b']);
      },
    );

    test(
      'change role and remove member; already-gone counts as done',
      () async {
        final (care, adapter) = await connected(
          danPays: true,
          more: [
            (
              200,
              {
                'member': {
                  'id': 'dan',
                  'name': 'Dan',
                  'role': 'sitter',
                  'joined': true,
                },
              },
            ),
            (
              404,
              {
                'error': 'That person already left the household.',
                'code': 'member_gone',
              },
            ),
          ],
        );
        expect(care.memberById('dan').paysForPro, isTrue);
        expect(await care.changeMemberRole('dan', MemberRole.sitter), isNull);
        expect(care.memberById('dan').role, MemberRole.sitter);
        expect(await care.removeMember('dan'), isNull);
        expect(care.members.any((m) => m.id == 'dan'), isFalse);
        expect(
          adapter.paths,
          containsAll(['PATCH /v1/members/dan', 'DELETE /v1/members/dan']),
        );
        expect(
          await care.changeMemberRole('dan', MemberRole.owner),
          "There's always exactly one owner.",
        );
      },
    );

    test(
      'joining with an expired code shows the server’s friendly words',
      () async {
        final adapter = StepAdapter([
          (
            404,
            {
              'error': 'That invite code expired. Ask for a new one.',
              'code': 'invite_expired',
            },
          ),
        ]);
        final api = HouseholdApi(
          Uri.parse('https://example.test'),
          dio: Dio()..httpClientAdapter = adapter,
        );
        final care = CareRepository(api: api, clock: () => _clock);
        expect(
          await care.join(code: 'OLD123', name: 'Dan'),
          'That invite code expired. Ask for a new one.',
        );
        expect(care.isConnected, isFalse);
        try {
          await api.join(code: 'OLD123', name: 'Dan');
        } on HouseholdException catch (error) {
          expect(
            error.isInviteExpired,
            isFalse,
            reason: 'replies exhausted → 500',
          );
        }
      },
    );
  });

  group('push registration', () {
    test('registers the real APNs token with its environment', () async {
      final (care, adapter) = await connected();
      final register = adapter.requests.firstWhere(
        (r) => r.path == '/v1/devices/register',
      );
      expect(register.data, {
        'platform': 'ios',
        'token': 'apns:$fakeApnsHex',
        'pushEnabled': true,
        'environment': 'sandbox',
      });
      expect(await PushService.remoteDeliveryActive(), isTrue);
      expectLogged('push.registered', fields: {'delivery': true});
      // The server pushes now: the local "partner logged" alert would double up.
      await PushService.notifyPartnerLogged(
        logId: 'log-9',
        who: 'Dan',
        medicationName: 'Insulin',
        petName: 'Miso',
      );
      expectLogged('push.partner_skipped', fields: {'reason': 'remote_push'});
      expect(care.isConnected, isTrue);
    });

    test(
      'launch re-registration only calls the server when something changed',
      () async {
        final (care, adapter) = await connected();
        final sent = adapter.requests.length;
        await care.refreshPushRegistration();
        expect(adapter.requests.length, sent);
        expectLogged('push.register_skipped', fields: {'reason': 'unchanged'});
        // A new token from APNs (e.g. after a restore) is sent once.
        (PushService.platform as FakePushPlatform).hex = 'ab' * 32;
        adapter.steps.add((200, {'ok': true, 'delivery': true}));
        await care.refreshPushRegistration();
        expect(adapter.requests.length, sent + 1);
      },
    );

    test(
      'a timed-out registration is not remembered, so it is retried',
      () async {
        final (care, adapter) = await connected();
        (PushService.platform as FakePushPlatform).hex = 'cd' * 32;
        adapter.steps
          ..add(timeout)
          ..add((200, {'ok': true, 'delivery': true}));
        await care.refreshPushRegistration();
        expectLogged('push.register_failed', fields: {'timedOut': true});
        await care.refreshPushRegistration();
        expect(
          adapter.paths.where((p) => p == 'POST /v1/devices/register'),
          hasLength(3),
        );
      },
    );

    test(
      'connect never waits on APNs; a late token registers itself',
      () async {
        final fake = PushService.platform as FakePushPlatform..hang = true;
        PushService.listen();
        final watch = Stopwatch()..start();
        final (care, adapter) = await connected();
        expect(watch.elapsed, lessThan(const Duration(seconds: 1)));
        expect(care.isConnected, isTrue);
        expectLogged('household.joined');
        expect(adapter.paths.where((p) => p.contains('devices')), isEmpty);
        // APNs answers later: registered in the background, once.
        fake.hang = false;
        fake.deliverToken('ef' * 32);
        await Future<void>.delayed(const Duration(milliseconds: 20));
        final register = adapter.requests.where(
          (r) => r.path == '/v1/devices/register',
        );
        expect(register.single.data['token'], 'apns:${'ef' * 32}');
        fake.deliverToken('ef' * 32);
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(
          adapter.requests.where((r) => r.path == '/v1/devices/register'),
          hasLength(1),
        );
      },
    );

    test(
      'no token (simulator / Android without Firebase): nothing is sent',
      () async {
        (PushService.platform as FakePushPlatform).hex = null;
        final (_, adapter) = await connected(more: const []);
        expect(adapter.paths.where((p) => p.contains('devices')), isEmpty);
        expectLogged('push.register_skipped', fields: {'reason': 'no_token'});
        expectLogged(
          'push.token_unavailable',
          fields: {'reason': 'no_token_yet'},
        );
      },
    );
  });

  group('push payloads', () {
    late List<int> cancelled;
    late List<List<PushDose>> refreshed;

    setUp(() {
      cancelled = [];
      refreshed = [];
      final fake = FakeReminderPlatform();
      DoseReminders.platform = fake;
      cancelled = fake.cancelled;
      PushService.onDosesLoggedElsewhere = (doses) async =>
          refreshed.add(doses);
      SharedPreferences.setMockInitialValues({
        'reminder_target_v1': jsonEncode({
          'doseId': 'insulin.morning',
          'day': '2026-10-04',
        }),
      });
    });

    Map<String, Object?> payload(
      String part, {
      String outcome = 'given',
      String day = '2026-10-04',
    }) => {
      'aps': {'content-available': 1},
      'type': 'dose_logged',
      'householdId': 'hh_test',
      'doses': [
        {
          'logId': 'log-1',
          'medicationId': 'insulin',
          'part': part,
          'day': day,
          'outcome': outcome,
        },
      ],
    };

    test('a dose someone else gave cancels exactly that reminder, once', () async {
      await PushService.handleRemoteMessage(payload('morning'));
      // Reminder, follow-up and snooze of exactly that dose-day, by id.
      expect(cancelled, [
        for (final kind in [
          ReminderKind.dose,
          ReminderKind.followUp,
          ReminderKind.snooze,
        ])
          ReminderIds.forDose(kind, 'insulin.morning', '2026-10-04'),
      ]);
      expect(refreshed.single.single.doseId, 'insulin.morning');
      // The alert and the silent push both arrive: cancelling is idempotent.
      await PushService.handleRemoteMessage(payload('morning'));
      expect(cancelled.toSet(), hasLength(3));
      expectLogged(
        'reminders.cancelled_by_push',
        fields: {'doseId': 'insulin.morning'},
      );
    });

    test(
      'a different dose, day, or a "not sure" leaves this reminder alone',
      () async {
        final mine = ReminderIds.forDose(
          ReminderKind.dose,
          'insulin.morning',
          '2026-10-04',
        );
        await PushService.handleRemoteMessage(
          payload('morning', outcome: 'uncertain'),
        );
        expect(cancelled, isEmpty, reason: '"not sure" keeps reminders up');
        await PushService.handleRemoteMessage(payload('evening'));
        await PushService.handleRemoteMessage(
          payload('morning', day: '2026-10-05'),
        );
        // Only those doses' own reminders go; this morning's stays.
        expect(cancelled, hasLength(6));
        expect(cancelled, isNot(contains(mine)));
        expect(
          refreshed,
          hasLength(3),
          reason: 'still refreshes the household',
        );
      },
    );

    test('junk payloads are ignored', () async {
      await PushService.handleRemoteMessage({'type': 'other'});
      await PushService.handleRemoteMessage({
        'type': 'dose_logged',
        'doses': 'nope',
      });
      await PushService.handleRemoteMessage({
        'type': 'dose_logged',
        'doses': [
          {'medicationId': 5},
        ],
      });
      expect(cancelled, isEmpty);
      expect(refreshed, isEmpty);
    });

    test('a failing refresh never escapes the push handler', () async {
      PushService.onDosesLoggedElsewhere = (_) async =>
          throw StateError('offline');
      await PushService.handleRemoteMessage(payload('morning'));
      expect(cancelled, hasLength(3), reason: 'cancelled before the refresh');
      expectLogged('push.refresh_failed');
    });
  });

  group('household screen', () {
    Future<void> pump(WidgetTester t, CareRepository care) async {
      // Tall enough that the member list is built (ListView is lazy).
      t.view.physicalSize = const Size(1200, 4000);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(
        ChangeNotifierProvider.value(
          value: care,
          child: const MaterialApp(home: HouseholdScreen()),
        ),
      );
      await t.pump();
    }

    testWidgets('owner gets Manage on other members; roles are shown', (
      t,
    ) async {
      late CareRepository care;
      await t.runAsync(() async => (care, _) = await connected());
      await pump(t, care);
      expect(find.text('Caregiver'), findsOneWidget);
      expect(find.byTooltip('Manage Dan'), findsOneWidget);
      expect(find.text('Ask the owner to invite people.'), findsNothing);
    });

    testWidgets('caregiver: no Manage, invite disabled with a hint', (t) async {
      late CareRepository care;
      await t.runAsync(
        () async =>
            (care, _) = await connected(me: 'dan', role: MemberRole.caregiver),
      );
      await pump(t, care);
      expect(find.byTooltip('Manage Sam'), findsNothing);
      expect(find.text('Ask the owner to invite people.'), findsOneWidget);
      final invite = t.widget<ButtonStyleButton>(
        find.ancestor(
          of: find.text('Invite someone'),
          matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
        ),
      );
      expect(invite.onPressed, isNull);
    });
  });
}
