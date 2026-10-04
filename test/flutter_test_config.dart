import 'dart:async';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pawsitive_sync/data/dose_reminders.dart';
import 'package:pawsitive_sync/data/local_database.dart';
import 'package:pawsitive_sync/data/push_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'fake_push_platform.dart';
import 'fake_reminder_platform.dart';

/// Runs before every test file: secure storage (Keychain / Keystore) and the
/// household database get a fresh in-memory copy per test, like
/// SharedPreferences mocks do.
///
/// The database runs on the host's SQLite in this isolate (no background
/// isolate, no file I/O), so it also works inside `testWidgets`' fake async.
/// One connection per test stands in for the file: a new `HouseholdStore`
/// in the same test sees what an earlier one saved, as after a relaunch.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  sqfliteFfiInit();
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    // Every test gets an iPhone-like push token (no platform channel here).
    PushService.platform = FakePushPlatform();
    PushService.resetForTest();
    PushService.onDosesLoggedElsewhere = null;
    // No notification plugin in tests: reminders go to an in-memory fake.
    DoseReminders.resetForTest();
    DoseReminders.platform = FakeReminderPlatform();
    // Not awaited: a previous widget test may have started a write inside
    // its fake-async zone that will never be pumped again.
    unawaited(LocalDatabase.shared.close().catchError((Object _) {}));
    LocalDatabase.shared = LocalDatabase(
      factory: databaseFactoryFfiNoIsolate,
      path: () async => inMemoryDatabasePath,
    );
  });
  await testMain();
}
