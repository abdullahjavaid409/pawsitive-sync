import 'dart:async';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

/// Runs before every test file: secure storage (Keychain / Keystore) gets a
/// fresh in-memory fake per test, like SharedPreferences mocks do.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  await testMain();
}
