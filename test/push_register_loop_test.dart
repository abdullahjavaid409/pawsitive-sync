import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:pawsitive_sync/core/logging/app_log.dart';
import 'package:pawsitive_sync/data/push_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_household_api.dart';
import 'fake_push_platform.dart';
import 'test_log_helpers.dart';

/// Real iOS answers "register" with the token AND re-reports it through
/// the `token` callback every time it is asked.
class _EchoingIos extends FakePushPlatform {
  @override
  Future<PushToken?> token() async {
    final token = await super.token();
    if (token != null) scheduleMicrotask(() => onToken?.call(token));
    return token;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppLog.enableTestCapture();
    PushService.resetForTest();
  });
  tearDown(AppLog.disableTestCapture);

  test('an echoed, unchanged token never loops: one server call', () async {
    final ios = _EchoingIos();
    PushService.platform = ios;
    PushService.listen();
    final adapter = FakeHouseholdAdapter([
      for (var i = 0; i < 50; i++) (200, {'ok': true, 'delivery': false}),
    ]);
    final api = fakeHouseholdApi(adapter, token: 'house-token');
    await PushService.registerIfConnected(api);
    await Future<void>.delayed(const Duration(milliseconds: 200));
    final calls = adapter.requests.where(
      (r) => r.path == '/v1/devices/register',
    );
    expect(calls, hasLength(1));
    expect(ios.tokenCalls, 1, reason: 'the OS is asked once, not in a loop');
  });

  test(
    'a burst of triggers registers once (no race past "unchanged")',
    () async {
      PushService.platform = FakePushPlatform();
      final adapter = FakeHouseholdAdapter([
        for (var i = 0; i < 20; i++) (200, {'ok': true, 'delivery': false}),
      ]);
      final api = fakeHouseholdApi(adapter, token: 'house-token');
      await Future.wait([
        for (var i = 0; i < 10; i++)
          PushService.registerIfConnected(api, force: false),
      ]);
      expect(
        adapter.requests.where((r) => r.path == '/v1/devices/register'),
        hasLength(1),
      );
      expectLogged('push.register_skipped', fields: {'reason': 'unchanged'});
    },
  );

  test('a genuinely new token (APNs rotated it) still registers', () async {
    final ios = FakePushPlatform();
    PushService.platform = ios;
    PushService.listen();
    final adapter = FakeHouseholdAdapter([
      for (var i = 0; i < 5; i++) (200, {'ok': true, 'delivery': false}),
    ]);
    final api = fakeHouseholdApi(adapter, token: 'house-token');
    await PushService.registerIfConnected(api);
    ios.deliverToken('ab' * 32);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(
      adapter.requests.where((r) => r.path == '/v1/devices/register'),
      hasLength(2),
    );
  });
}
