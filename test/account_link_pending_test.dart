import 'package:flutter_test/flutter_test.dart';
import 'package:pawsitive_sync/core/logging/app_log.dart';
import 'package:pawsitive_sync/data/account_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_log_helpers.dart';

/// A save/restore the app was killed in the middle of must not leave the
/// phone signed in to an account that saves nothing here.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppLog.enableTestCapture();
  });
  tearDown(AppLog.disableTestCapture);

  test('interrupted link: next launch signs out and clears the mark', () async {
    await AccountService.markLinkPending(true);

    await AccountService.clearInterruptedLink();

    expectLogged('account.link_interrupted');
    expectLogged('account.signed_out');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('account_link_pending_v1'), isNull);
  });

  test('a finished link leaves nothing to clean up', () async {
    await AccountService.markLinkPending(true);
    await AccountService.markLinkPending(false);

    await AccountService.clearInterruptedLink();

    expectNotLogged('account.link_interrupted');
    expectNotLogged('account.signed_out');
  });
}
