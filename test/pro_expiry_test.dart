import 'package:flutter_test/flutter_test.dart';
import 'package:pawsitive_sync/core/logging/app_log.dart';
import 'package:pawsitive_sync/data/care_repository.dart';
import 'package:pawsitive_sync/data/household_store.dart';
import 'package:pawsitive_sync/data/revenue_cat_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_household_api.dart';
import 'test_log_helpers.dart';

/// Pro must end when the subscription ends — on the phone too, offline,
/// after a relaunch, with no extra API call.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppLog.enableTestCapture();
    RevenueCatService.storeProExpiresAt = null;
  });
  tearDown(() {
    AppLog.disableTestCapture();
    RevenueCatService.storeProExpiresAt = null;
  });

  var now = DateTime.utc(2026, 10, 4, 12);
  DateTime clock() => now;

  Map<String, Object?> body({bool pro = true, Object? proUntil = 'absent'}) {
    final base = connectHouseholdBody(isPro: pro);
    final house = {...(base['household']! as Map<String, Object?>)};
    if (proUntil != 'absent') house['proUntil'] = proUntil;
    return {...base, 'household': house};
  }

  Future<CareRepository> joined(Map<String, Object?> reply) async {
    final care = CareRepository(
      api: fakeHouseholdApi(FakeHouseholdAdapter([(200, reply), (200, {})])),
      store: HouseholdStore(),
      clock: clock,
    );
    expect(await care.join(code: 'ABC234', name: 'Me'), isNull);
    return care;
  }

  test('store entitlement: active only before its own expiry', () {
    final t = DateTime.utc(2026, 10, 4, 12);
    expect(
      RevenueCatService.proActive(
        rcActive: true,
        expirationDate: '2026-10-04T12:00:01Z',
        now: t,
      ),
      isTrue,
    );
    expect(
      RevenueCatService.proActive(
        rcActive: true,
        expirationDate: '2026-10-04T11:59:59Z',
        now: t,
      ),
      isFalse,
      reason: 'cached "active" past its end is not Pro',
    );
    expect(
      RevenueCatService.proActive(rcActive: true, expirationDate: null, now: t),
      isTrue,
      reason: 'lifetime',
    );
    expect(
      RevenueCatService.proActive(rcActive: false, expirationDate: null, now: t),
      isFalse,
    );
  });

  test('this phone’s subscription ends at its expiry even if the SDK never says so', () {
    now = DateTime.utc(2026, 10, 4, 12);
    final care = CareRepository(clock: clock)..debugStorePro = true;
    RevenueCatService.storeProExpiresAt = DateTime.utc(2026, 10, 4, 13);
    expect(care.isPro, isTrue);
    now = DateTime.utc(2026, 10, 4, 13);
    expect(care.isPro, isFalse);
  });

  test('household Pro ends at proUntil offline — and after a relaunch', () async {
    now = DateTime.utc(2026, 10, 4, 12);
    final care = await joined(body(proUntil: '2026-10-05T12:00:00.000Z'));
    expect(care.isPro, isTrue);
    now = DateTime.utc(2026, 10, 5, 11, 59);
    expect(care.isPro, isTrue);
    now = DateTime.utc(2026, 10, 5, 12);
    expect(care.isPro, isFalse, reason: 'no network needed to end it');
    await Future<void>.delayed(const Duration(milliseconds: 50));
    // Cold launch, still offline: the saved end still applies.
    final relaunched = CareRepository(
      api: fakeHouseholdApi(FakeHouseholdAdapter([]), token: 'house-token'),
      store: HouseholdStore(),
      clock: clock,
    );
    await relaunched.restore();
    expect(relaunched.isConnected, isTrue);
    expect(relaunched.isPro, isFalse);
    now = DateTime.utc(2026, 10, 5, 8);
    expect(relaunched.isPro, isTrue, reason: 'restored end time, not a flag');
  });

  test('winding the clock back behind the last sync doesn’t keep Pro offline', () async {
    now = DateTime.utc(2026, 10, 4, 12);
    final care = await joined(body(proUntil: '2026-10-05T12:00:00.000Z'));
    now = DateTime.utc(2026, 10, 4, 11, 30);
    expect(care.isPro, isTrue, reason: 'small corrections are tolerated');
    now = DateTime.utc(2026, 9, 1);
    expect(care.isPro, isFalse);
  });

  test('server says Free: Free, whatever proUntil a stale copy had', () async {
    now = DateTime.utc(2026, 10, 4, 12);
    final care = await joined(body(pro: false));
    expect(care.isPro, isFalse);
  });

  test('lifetime (null) and older servers (absent) keep the flag’s answer', () async {
    now = DateTime.utc(2026, 10, 4, 12);
    final lifetime = await joined(body(proUntil: null));
    now = DateTime.utc(2030, 1, 1);
    expect(lifetime.isPro, isTrue);
    SharedPreferences.setMockInitialValues({});
    now = DateTime.utc(2026, 10, 4, 12);
    final old = await joined(body());
    expect(old.isPro, isTrue);
  });

  test('the app flips to Free at the exact end while open and logs it once', () async {
    final start = DateTime.now().toUtc();
    final care = CareRepository(
      api: fakeHouseholdApi(
        FakeHouseholdAdapter([
          (
            200,
            body(
              proUntil: start
                  .add(const Duration(milliseconds: 300))
                  .toIso8601String(),
            ),
          ),
          (200, {}),
        ]),
      ),
      store: HouseholdStore(),
    );
    expect(await care.join(code: 'ABC234', name: 'Me'), isNull);
    expect(care.isPro, isTrue);
    var notified = 0;
    care.addListener(() => notified++);
    await Future<void>.delayed(const Duration(milliseconds: 1600));
    expect(care.isPro, isFalse);
    expect(notified, greaterThan(0), reason: 'UI and reminders re-read it');
    expectLogged('billing.pro.expired', fields: {'source': 'household'});
  });
}
