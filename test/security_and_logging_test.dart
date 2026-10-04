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
    test('legacy plain-text token migrates once and leaves preferences', () async {
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
      expect(await SecureTokens.read(SecureTokens.householdKey), 'legacy-token');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('household_v2'), isNot(contains('legacy-token')));
      expectLogged('store.token_migrated');

      // Second launch reads it from secure storage only.
      final again = CareRepository(
        api: HouseholdApi(Uri.parse('https://example.test')),
        store: HouseholdStore(),
      );
      await again.restore();
      expect(again.isConnected, isTrue);
    });

    test('a connected household never writes its token to preferences', () async {
      final care = CareRepository(
        api: fakeHouseholdApi(FakeHouseholdAdapter([
          (201, connectHouseholdBody()),
          (200, {'ok': true}),
        ])),
        store: HouseholdStore(),
        clock: _clock,
      );
      await care.addPet(name: 'Milo', species: Species.cat);
      expect(await care.connect(), isNull);
      await care.flushPersist();

      final prefs = await SharedPreferences.getInstance();
      for (final key in prefs.getKeys()) {
        expect('${prefs.get(key)}', isNot(contains('house-token')), reason: key);
      }
      expect(await SecureTokens.read(SecureTokens.householdKey), 'house-token');
    });

    test('fresh install drops a token orphaned by a previous install', () async {
      FlutterSecureStorage.setMockInitialValues({
        SecureTokens.householdKey: 'old-install-token',
      });
      expect(await HouseholdStore().read(), isNull);
      expect(await SecureTokens.read(SecureTokens.householdKey), isNull);
    });

    test('reset removes the token and cached sitter tokens', () async {
      final care = CareRepository(
        api: fakeHouseholdApi(FakeHouseholdAdapter([
          (201, connectHouseholdBody()),
          (200, {'ok': true}),
          (201, {'token': 'sitter-tok', 'expiresAt': '2026-11-03T00:00:00Z'}),
        ])),
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
        'sitter-tok',
      );
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getKeys().where((k) => k.startsWith('sitter_web_token')), isEmpty);

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
        api: fakeHouseholdApi(FakeHouseholdAdapter([
          (201, connectHouseholdBody()),
          (200, {'ok': true}),
        ])),
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
    test('stale saved household Pro is ignored without a household link', () async {
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
    });

    test('unlock logs billing.pro.unlocked once and never a share step', () async {
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
    });

    test('plan change on a solo phone is local, not "offline"', () async {
      final care = CareRepository(clock: _clock);
      await care.setPlan(BillingPlan.monthly);
      expectLogged('billing.plan.completed', fields: {'local': true});
      expect(
        AppLog.testRecords.any(
          (r) => r.name == 'billing.plan.completed' && r.fields['offline'] == true,
        ),
        isFalse,
      );
    });

    test('connected phone shares its Pro with the household', () async {
      final care = CareRepository(
        api: fakeHouseholdApi(FakeHouseholdAdapter([
          (201, connectHouseholdBody(isPro: false)),
          (200, {'ok': true}), // push register
          (200, {'isPro': true, 'plan': 'yearly'}), // share Pro
        ])),
        clock: _clock,
      );
      await care.addPet(name: 'Milo', species: Species.cat);
      await care.connect();
      care.applyStoreEntitlement(true, BillingPlan.yearly);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expectLogged('billing.share_pro.completed', fields: {'householdPro': true});
      expect(AppLog.logCount('billing.pro.unlocked'), 1);
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

    test('RevenueCat SDK output: warn/error forwarded redacted, debug dropped', () {
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
    });
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
}
