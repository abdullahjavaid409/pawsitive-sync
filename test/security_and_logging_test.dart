import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pawsitive_sync/core/logging/app_log.dart';
import 'package:pawsitive_sync/data/care_repository.dart';
import 'package:pawsitive_sync/data/household_api.dart';
import 'package:pawsitive_sync/data/household_store.dart';
import 'package:pawsitive_sync/data/revenue_cat_service.dart';
import 'package:pawsitive_sync/data/secure_tokens.dart';
import 'package:pawsitive_sync/domain/models.dart';
import 'package:purchases_flutter/purchases_flutter.dart' show LogLevel;
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_household_api.dart';
import 'test_log_helpers.dart';

const _clockTime = (2026, 10, 3, 14);
DateTime _clock() =>
    DateTime(_clockTime.$1, _clockTime.$2, _clockTime.$3, _clockTime.$4);

Map<String, Object?> _savedHousehold({String? token, bool isPro = false}) => {
  'householdId': 'hh_1',
  'token': ?token,
  'memberId': 'you',
  'inviteCode': 'ABC234',
  'isPro': isPro,
  'plan': 'yearly',
  'members': [
    {'id': 'you', 'name': 'You', 'role': 'owner', 'isYou': true},
  ],
  'pets': [
    {'id': 'miso', 'name': 'Miso', 'species': 'cat'},
  ],
  'medications': <Object>[],
  'logs': <Object>[],
};

/// Counts store writes to prove a burst of changes is saved once.
class _CountingStore extends HouseholdStore {
  int writes = 0;

  @override
  Future<void> write(StoredHousehold house) {
    writes++;
    return super.write(house);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppLog.enableTestCapture();
  });
  tearDown(AppLog.disableTestCapture);

  group('Household token lives in secure storage', () {
    test(
      'legacy plain-text token migrates once and leaves preferences',
      () async {
        SharedPreferences.setMockInitialValues({
          'household_v2': jsonEncode(_savedHousehold(token: 'legacy-token')),
        });
        final care = CareRepository(
          api: HouseholdApi(Uri.parse('https://example.test')),
          store: HouseholdStore(),
          clock: _clock,
        );
        await care.restore();

        expect(care.isConnected, isTrue);
        expect(
          await SecureTokens.read(SecureTokens.householdKey),
          'legacy-token',
        );
        final prefs = await SharedPreferences.getInstance();
        expect(
          prefs.getString('household_v2'),
          isNot(contains('legacy-token')),
        );
        expectLogged('store.token_migrated');

        // Second launch reads it from secure storage only.
        final again = CareRepository(
          api: HouseholdApi(Uri.parse('https://example.test')),
          store: HouseholdStore(),
        );
        await again.restore();
        expect(again.isConnected, isTrue);
      },
    );

    test(
      'a connected household never writes its token to preferences',
      () async {
        final care = CareRepository(
          api: fakeHouseholdApi(
            FakeHouseholdAdapter([
              (201, connectHouseholdBody()),
              (200, {'ok': true}),
            ]),
          ),
          store: HouseholdStore(),
          clock: _clock,
        );
        await care.addPet(name: 'Milo', species: Species.cat);
        expect(await care.connect(), isNull);
        await care.flushPersist();

        final prefs = await SharedPreferences.getInstance();
        for (final key in prefs.getKeys()) {
          expect(
            '${prefs.get(key)}',
            isNot(contains('house-token')),
            reason: key,
          );
        }
        expect(
          await SecureTokens.read(SecureTokens.householdKey),
          'house-token',
        );
      },
    );

    test(
      'fresh install drops a token orphaned by a previous install',
      () async {
        FlutterSecureStorage.setMockInitialValues({
          SecureTokens.householdKey: 'old-install-token',
        });
        expect(await HouseholdStore().read(), isNull);
        expect(await SecureTokens.read(SecureTokens.householdKey), isNull);
      },
    );

    test('reset removes the token and cached sitter tokens', () async {
      final care = CareRepository(
        api: fakeHouseholdApi(
          FakeHouseholdAdapter([
            (201, connectHouseholdBody()),
            (200, {'ok': true}),
            (201, {'token': 'sitter-tok', 'expiresAt': '2026-11-03T00:00:00Z'}),
          ]),
        ),
        store: HouseholdStore(),
        clock: _clock,
      );
      await care.addPet(name: 'Milo', species: Species.cat);
      care.applyStoreEntitlement(true, BillingPlan.yearly);
      await care.connect();
      final link = await care.ensureSitterWebLink();
      expect(link, contains('/sitter#t=sitter-tok'));
      expect(
        await SecureTokens.read('${SecureTokens.sitterKeyPrefix}:ABC234'),
        contains('"token":"sitter-tok"'),
      );
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getKeys().where((k) => k.startsWith('sitter_web_token')),
        isEmpty,
      );

      await care.reset();
      expect(await SecureTokens.read(SecureTokens.householdKey), isNull);
      expect(
        await SecureTokens.read('${SecureTokens.sitterKeyPrefix}:ABC234'),
        isNull,
      );
    });

    test('legacy cached sitter token moves out of preferences', () async {
      SharedPreferences.setMockInitialValues({
        'sitter_web_token_v1:ABC234': 'old-sitter-token',
      });
      final care = CareRepository(
        api: fakeHouseholdApi(
          FakeHouseholdAdapter([
            (201, connectHouseholdBody()),
            (200, {'ok': true}),
          ]),
        ),
        clock: _clock,
      );
      await care.addPet(name: 'Milo', species: Species.cat);
      care.applyStoreEntitlement(true, BillingPlan.yearly);
      await care.connect();
      expect(await care.ensureSitterWebLink(), contains('#t=old-sitter-token'));
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('sitter_web_token_v1:ABC234'), isNull);
      expectLogged('sitter.token_migrated');
      expectLogged('sitter.link_cached');
    });
  });

  group('Billing logs on a solo phone', () {
    test(
      'stale saved household Pro is ignored without a household link',
      () async {
        SharedPreferences.setMockInitialValues({
          'household_v2': jsonEncode(_savedHousehold(isPro: true)),
        });
        final care = CareRepository(store: HouseholdStore(), clock: _clock);
        await care.restore();
        expect(care.isPro, isFalse);

        care.applyStoreEntitlement(true, BillingPlan.monthly);
        final changed = AppLog.testRecords.singleWhere(
          (r) => r.name == 'billing.store.entitlement_changed',
        );
        expect(changed.fields.containsKey('serverPro'), isFalse);
        expect(changed.fields.containsKey('householdPro'), isFalse);
      },
    );

    test(
      'unlock logs billing.pro.unlocked once and never a share step',
      () async {
        final care = CareRepository(clock: _clock);
        await care.addPet(name: 'Milo', species: Species.cat);
        care.applyStoreEntitlement(true, BillingPlan.monthly);
        await care.startTrial(); // what purchase/restore call after unlocking

        expect(AppLog.logCount('billing.pro.unlocked'), 1);
        expect(
          AppLog.testRecords.where(
            (r) =>
                r.name.startsWith('billing.share_pro') ||
                r.name.startsWith('billing.trial'),
          ),
          isEmpty,
        );
      },
    );

    test('plan change on a solo phone is local, not "offline"', () async {
      final care = CareRepository(clock: _clock);
      await care.setPlan(BillingPlan.monthly);
      expectLogged('billing.plan.completed', fields: {'local': true});
      expect(
        AppLog.testRecords.any(
          (r) =>
              r.name == 'billing.plan.completed' && r.fields['offline'] == true,
        ),
        isFalse,
      );
    });

    test('connected phone shares its Pro with the household', () async {
      final care = CareRepository(
        api: fakeHouseholdApi(
          FakeHouseholdAdapter([
            (201, connectHouseholdBody(isPro: false)),
            (200, {'ok': true}), // push register
            (200, {'isPro': true, 'plan': 'yearly'}), // share Pro
          ]),
        ),
        clock: _clock,
      );
      await care.addPet(name: 'Milo', species: Species.cat);
      await care.connect();
      care.applyStoreEntitlement(true, BillingPlan.yearly);
      // The share runs unawaited from the store listener.
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expectLogged(
        'billing.share_pro.completed',
        fields: {'householdPro': true},
      );
      expect(AppLog.logCount('billing.pro.unlocked'), 1);
    });
  });

  group('Carrying Pro into a household', () {
    tearDown(() => RevenueCatService.debugOnIdentify = null);

    test(
      'store account is identified before Pro is pushed to the server',
      () async {
        final adapter = FakeHouseholdAdapter([
          (201, connectHouseholdBody(isPro: false, householdId: 'hh_9')),
          (200, {'isPro': false, 'plan': 'yearly'}), // webhook not seen yet
          (200, {'ok': true}), // push register
        ]);
        final order = <String>[];
        RevenueCatService.debugOnIdentify = (id) {
          order.add('identify:$id@${adapter.requests.length}');
        };
        final care = CareRepository(
          api: fakeHouseholdApi(adapter),
          clock: _clock,
        );
        await care.addPet(name: 'Milo', species: Species.cat);
        care.applyStoreEntitlement(true, BillingPlan.yearly);
        expect(await care.connect(), isNull);

        final trialAt = adapter.requests.indexWhere(
          (r) => r.path == '/v1/billing/trial',
        );
        expect(trialAt, 1);
        // First identify happened after POST /v1/households (1 request) and
        // before POST /v1/billing/trial.
        expect(order.first, 'identify:hh_9:you@1');
        expectLogged('billing.pro.carry_pending', fields: {'isPro': false});
        expectNotLogged('billing.pro.carried_online');
      },
    );

    test(
      'sitter link 403 shares Pro once, retries once, then explains',
      () async {
        final adapter = FakeHouseholdAdapter([
          (201, connectHouseholdBody(isPro: true)),
          (200, {'ok': true}), // push register
          (403, {'error': 'Browser sitter links need Pawsitive Pro.'}),
          (200, {'isPro': false, 'plan': 'yearly'}), // share Pro: still Free
          (403, {'error': 'Browser sitter links need Pawsitive Pro.'}),
        ]);
        final care = CareRepository(
          api: fakeHouseholdApi(adapter),
          clock: _clock,
        );
        await care.addPet(name: 'Milo', species: Species.cat);
        care.applyStoreEntitlement(true, BillingPlan.yearly);
        await care.connect();
        AppLog.testRecords.clear();

        final results = await Future.wait([
          care.ensureSitterWebLink(),
          care.ensureSitterWebLink(), // concurrent tap: shares the request
        ]);
        expect(results, [isNull, isNull]);
        expect(
          adapter.requests.where((r) => r.path == '/v1/sitter-links'),
          hasLength(2),
          reason: 'one request + one retry, never more',
        );
        expectLogged('sitter.link_retry');
        expectLogged('sitter.link_failed', fields: {'status': 403});
        expect(care.lastError, contains('still being set up'));
      },
    );

    test('sitter link 403 then success after sharing Pro', () async {
      final adapter = FakeHouseholdAdapter([
        (201, connectHouseholdBody(isPro: true)),
        (200, {'ok': true}),
        (403, {'error': 'Browser sitter links need Pawsitive Pro.'}),
        (200, {'isPro': true, 'plan': 'yearly'}),
        (201, {'token': 'tok-ok', 'expiresAt': '2026-11-03T00:00:00Z'}),
      ]);
      final care = CareRepository(
        api: fakeHouseholdApi(adapter),
        clock: _clock,
      );
      await care.addPet(name: 'Milo', species: Species.cat);
      care.applyStoreEntitlement(true, BillingPlan.yearly);
      await care.connect();
      expect(await care.ensureSitterWebLink(), endsWith('/sitter#t=tok-ok'));
      expectLogged('sitter.link_created');
    });
  });

  group('No personal data in logs', () {
    test('partner dose detection logs ids, never the partner name', () async {
      final care = CareRepository(
        api: fakeHouseholdApi(
          FakeHouseholdAdapter([
            (
              200,
              connectHouseholdBody(
                logs: [
                  {
                    'id': 'log-p1',
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
          ]),
          token: 'house-token',
        ),
        clock: _clock,
      );
      await care.sync(force: true);
      final detected = AppLog.testRecords.singleWhere(
        (r) => r.name == 'push.partner_detected',
      );
      expect(detected.fields, {'logId': 'log-p1', 'memberId': 'dan'});
      expect(detected.fields.values, isNot(contains('Dan')));
    });

    test('redact strips JWS, RevenueCat ids, bearer tokens and emails', () {
      const jws =
          'eyJhbGciOiJFUzI1NiIsIng1YyI6WyJNSUlFTURDQ0E3YWdBd0lCQWdJUWZUbGZk.'
          'eyJ0cmFuc2FjdGlvbklkIjoiMjAwMDAwMDcxMjM0In0.c2lnbmF0dXJl';
      final out = AppLog.redact(
        'tx $jws user \$RCAnonymousID:8f2a9c0d1e mail a.b@example.com '
        'Authorization: Bearer abc.def link /sitter#t=secret123',
      );
      expect(out, isNot(contains('eyJ')));
      expect(out, isNot(contains('8f2a9c0d1e')));
      expect(out, isNot(contains('example.com')));
      expect(out, isNot(contains('abc.def')));
      expect(out, isNot(contains('secret123')));
      expect(AppLog.redact('x' * 500).length, lessThanOrEqualTo(161));
    });

    test(
      'RevenueCat SDK output: warn/error forwarded redacted, debug dropped',
      () {
        RevenueCatService.onSdkLogForTest(LogLevel.debug, 'attributes: {...}');
        RevenueCatService.onSdkLogForTest(
          LogLevel.warn,
          'Receipt eyJhbGciOiJFUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxIn0.sig '
          'for \$RCAnonymousID:abcdef123',
        );
        expect(AppLog.logCount('billing.rc.sdk'), 1);
        final line = AppLog.testRecords.single;
        expect(line.fields['level'], 'warn');
        expect('${line.fields['message']}', isNot(contains('eyJ')));
        expect('${line.fields['message']}', isNot(contains('abcdef123')));
      },
    );
  });

  group('Persistence', () {
    test('a burst of offline dose logs is saved in one write', () async {
      final store = _CountingStore();
      final care = CareRepository(store: store, clock: _clock);
      final petId = await care.addPet(name: 'Milo', species: Species.cat);
      for (var i = 0; i < 10; i++) {
        await care.addMedication(
          petId: petId!,
          name: 'Med $i',
          amount: '1',
          parts: const [DayPart.morning],
        );
      }
      await care.flushPersist();
      store.writes = 0;

      final logs = [
        for (final dose in care.doses)
          care.logDose(
            doseId: dose.id,
            memberId: 'you',
            amount: dose.amount,
            timeLabel: '2:00 PM',
          ),
      ];
      expect(await Future.wait(logs), everyElement(isTrue));
      await care.flushPersist();
      expect(store.writes, 1, reason: '10 changes in one turn → one save');

      final reloaded = CareRepository(store: HouseholdStore(), clock: _clock);
      await reloaded.restore();
      expect(reloaded.logs, hasLength(10));
    });
  });

  group('Named sitter links', () {
    Future<(CareRepository, FakeHouseholdAdapter)> proCare() async {
      final adapter = FakeHouseholdAdapter([
        (201, connectHouseholdBody(isPro: true)),
        (200, {'ok': true}),
        (201, {'token': 'tok-1', 'expiresAt': '2026-11-03T00:00:00Z'}),
      ]);
      final care = CareRepository(
        api: fakeHouseholdApi(adapter),
        clock: _clock,
      );
      await care.addPet(name: 'Milo', species: Species.cat);
      care.applyStoreEntitlement(true, BillingPlan.yearly);
      await care.connect();
      AppLog.testRecords.clear();
      return (care, adapter);
    }

    Object? sentLabel(FakeHouseholdAdapter adapter) =>
        (adapter.requests.lastWhere((r) => r.path == '/v1/sitter-links').data
            as Map)['label'];

    test('default label is used when the field is left as is', () async {
      final (care, adapter) = await proCare();
      expect(care.defaultSitterLabel(), 'Sitter · Oct 3');
      await care.ensureSitterWebLink(label: care.defaultSitterLabel());
      expect(sentLabel(adapter), 'Sitter · Oct 3');
      expect(care.sitterLink!.label, 'Sitter · Oct 3');
      expect(care.sitterLink!.expiresAt, DateTime.utc(2026, 11, 3));
      expectLogged('sitter.link_created', fields: {'hasCustomName': false});
    });

    test('blank label falls back to the default', () async {
      final (care, adapter) = await proCare();
      await care.ensureSitterWebLink(label: '   ');
      expect(sentLabel(adapter), 'Sitter · Oct 3');
    });

    test('custom label is sent and never logged', () async {
      final (care, adapter) = await proCare();
      await care.ensureSitterWebLink(label: '  Sara — weekend sitter ');
      expect(sentLabel(adapter), 'Sara — weekend sitter');
      expectLogged('sitter.link_created', fields: {'hasCustomName': true});
      for (final r in AppLog.testRecords) {
        expect(r.fields.values.join(' '), isNot(contains('Sara')));
      }
    });

    test('label longer than 40 characters is trimmed', () async {
      final (care, adapter) = await proCare();
      await care.ensureSitterWebLink(label: 'A' * 55);
      expect(sentLabel(adapter), 'A' * 40);
      expect(care.normalizeSitterLabel('x' * 41).length, 40);
    });

    test(
      'name and expiry survive a restart; loading never calls the server',
      () async {
        final (care, adapter) = await proCare();
        await care.ensureSitterWebLink(label: 'Sara');
        final calls = adapter.requests.length;
        final link = await care.loadSitterLink();
        expect(link!.label, 'Sara');
        expect(link.url, endsWith('#t=tok-1'));
        expect(adapter.requests.length, calls);
      },
    );

    test('free phone never loads or requests a link', () async {
      final care = CareRepository(clock: _clock);
      expect(await care.loadSitterLink(), isNull);
    });
  });

  group('Launch billing for a connected subscriber', () {
    test(
      'no share call, no unlock line when the server already says Pro',
      () async {
        final adapter = FakeHouseholdAdapter([
          (201, connectHouseholdBody(isPro: true)),
          (200, {'ok': true}),
        ]);
        final first = CareRepository(
          api: fakeHouseholdApi(adapter),
          store: HouseholdStore(),
          clock: _clock,
        );
        await first.addPet(name: 'Milo', species: Species.cat);
        await first.restore();
        first.applyStoreEntitlement(true, BillingPlan.yearly);
        await first.connect();
        await first.flushPersist();
        await Future<void>.delayed(const Duration(milliseconds: 20));

        // Next launch: RevenueCat reports the existing subscription.
        AppLog.testRecords.clear();
        final relaunchAdapter = FakeHouseholdAdapter([]);
        final again = CareRepository(
          api: fakeHouseholdApi(relaunchAdapter),
          store: HouseholdStore(),
          clock: _clock,
        );
        await again.restore();
        expect(
          again.isPro,
          isTrue,
          reason: 'saved household Pro kept when linked',
        );
        again.applyStoreEntitlement(true, BillingPlan.yearly);
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(
          relaunchAdapter.requests,
          isEmpty,
          reason: 'no POST /v1/billing/trial',
        );
        expectNotLogged('billing.pro.unlocked');
        expectLogged('billing.pro.active');
      },
    );

    test('store plan wins over a stale server plan', () async {
      final adapter = FakeHouseholdAdapter([
        (201, connectHouseholdBody(isPro: true)), // server plan: yearly
        (200, {'ok': true}),
        (200, {'plan': 'monthly'}), // setPlan push
        (200, connectHouseholdBody(isPro: true)), // later sync, still yearly
      ]);
      final care = CareRepository(
        api: fakeHouseholdApi(adapter),
        clock: _clock,
      );
      await care.addPet(name: 'Milo', species: Species.cat);
      await care.connect();
      care.applyStoreEntitlement(true, BillingPlan.monthly);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(care.plan, BillingPlan.monthly);
      expect(
        adapter.requests.where((r) => r.path == '/v1/billing/plan'),
        hasLength(1),
      );
      await care.sync(force: true);
      expect(
        care.plan,
        BillingPlan.monthly,
        reason: 'server snapshot must not overwrite',
      );
    });

    test('sync that finds the household Free shares Pro once', () async {
      final adapter = FakeHouseholdAdapter([
        (200, connectHouseholdBody(isPro: false)),
        (200, {'isPro': true, 'plan': 'yearly'}),
      ]);
      final care = CareRepository(
        api: fakeHouseholdApi(adapter, token: 'house-token'),
        clock: _clock,
      );
      care.applyStoreEntitlement(true, BillingPlan.yearly);
      expect(adapter.requests, isEmpty, reason: 'no share before a sync');
      await care.sync(force: true);
      expect(
        adapter.requests.where((r) => r.path == '/v1/billing/trial'),
        hasLength(1),
      );
      expect(care.isPro, isTrue);
    });
  });
}
