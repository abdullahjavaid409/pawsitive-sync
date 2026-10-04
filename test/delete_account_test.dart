import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pawsitive_sync/core/logging/app_log.dart';
import 'package:pawsitive_sync/data/analytics_service.dart';
import 'package:pawsitive_sync/data/care_repository.dart';
import 'package:pawsitive_sync/data/dose_reminders.dart';
import 'package:pawsitive_sync/data/household_api.dart';
import 'package:pawsitive_sync/data/household_store.dart';
import 'package:pawsitive_sync/data/onboarding_state.dart';
import 'package:pawsitive_sync/data/pet_photo_store.dart';
import 'package:pawsitive_sync/data/reminder_choice.dart';
import 'package:pawsitive_sync/data/secure_tokens.dart';
import 'package:pawsitive_sync/data/sync_engine.dart';
import 'package:pawsitive_sync/data/sync_outbox.dart';
import 'package:pawsitive_sync/data/upgrade_nudge_state.dart';
import 'package:pawsitive_sync/data/whats_new_state.dart';
import 'package:pawsitive_sync/domain/models.dart';
import 'package:pawsitive_sync/ui/onboarding/onboarding_view_model.dart';
import 'package:pawsitive_sync/ui/settings/settings_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_reminder_platform.dart';
import 'photo_test_helpers.dart';
import 'support/sample_household.dart';

const _notifications = MethodChannel(
  'dexterous.com/flutter/local_notifications',
);
const _widgets = MethodChannel('pawsitive_sync/widgets');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  final notificationCalls = <String>[];
  late FakeReminderPlatform reminders;
  final widgetPayloads = <String>[];

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    AppLog.enableTestCapture();
    CareRepository.photoRetryDelays = const [];
    dir = await Directory.systemTemp.createTemp('delete_account_test');
    notificationCalls.clear();
    widgetPayloads.clear();
    reminders = FakeReminderPlatform();
    DoseReminders.platform = reminders;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_notifications, (call) async {
      notificationCalls.add(call.method);
      return call.method == 'initialize' ? true : null;
    });
    messenger.setMockMethodCallHandler(_widgets, (call) async {
      widgetPayloads.add('${call.arguments}');
      return null;
    });
  });

  tearDown(() async {
    AppLog.disableTestCapture();
    debugDefaultTargetPlatformOverride = null;
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  Future<(CareRepository, RouteAdapter)> owner(
    Map<String, List<RouteResult>> routes, {
    String role = 'owner',
  }) async {
    final (care, adapter, _) = await connectedCare(
      dir,
      snapshot: role == 'owner'
          ? snapshotWithPhoto()
          : snapshotWithPhoto(memberId: 'sam', role: role),
      routes: routes,
    );
    return (care, adapter);
  }

  bool photosOnDisk() =>
      Directory('${dir.path}/${PetPhotoStore.ownFolder}').existsSync() ||
      Directory('${dir.path}/${PetPhotoStore.cacheFolder}').existsSync();

  test('owner: server first, then every local trace is wiped', () async {
    // iOS so the home-screen widget bridge is exercised.
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    IOSFlutterLocalNotificationsPlugin.registerWith();
    final (care, adapter) = await owner({
      'DELETE /v1/account': [
        const Answer(200, {'deleted': true, 'scope': 'household'}),
      ],
      ...uploadRoutes('households/h/pets/miso/z.jpg'),
    });
    // Seed everything deleteAccount must remove.
    await care.setPetPhoto('miso', sampleJpeg(48, 48));
    await PetPhotoStore(baseDir: () async => dir)
        .writeCache('households/h/pets/miso/other.jpg', sampleJpeg(8, 8));
    await care.addCareEvent(
      petId: 'miso',
      title: 'Vaccine',
      kind: CareEventKind.vaccine,
      dueDate: DateTime(2030),
    );
    await SyncOutbox().enqueue(
      const SyncBatchOp(id: 'op-1', type: 'refill', payload: {'id': 'x'}),
    );
    await SecureTokens.write('${SecureTokens.sitterKeyPrefix}:ABC234', 'tok');
    await OnboardingState.write(true);
    final model = OnboardingViewModel()..petName = 'Miso';
    await model.finish(reminders: true); // profile + reminder choice
    await WhatsNewState.markSeen();
    await UpgradeNudgeState.dismiss();
    await ReminderChoice.write(true);
    AnalyticsService.debugAdd('dose.log.completed');
    await care.flushPersist();
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getKeys(), isNotEmpty);
    expect(photosOnDisk(), isTrue);

    expect(await care.deleteAccount(), isNull);

    // Server was asked before anything local went.
    expect(adapter.calls, contains('DELETE /v1/account'));
    expect(
      AppLog.testRecords.indexWhere(
        (r) => r.name == 'account.delete_requested',
      ),
      lessThan(
        AppLog.testRecords.indexWhere((r) => r.name == 'household.reset'),
      ),
    );
    expect(AppLog.testRecords.last.name, 'account.deleted');
    expect(AppLog.testRecords.last.fields['scope'], 'household');

    // Nothing left: preferences, secrets, photos, memory, reminders, widget.
    final after = await SharedPreferences.getInstance();
    expect(after.getKeys(), isEmpty);
    expect(await const FlutterSecureStorage().readAll(), isEmpty);
    expect(await HouseholdStore().read(), isNull);
    expect(await SyncOutbox().read(), isEmpty);
    expect(await OnboardingState.read(), isFalse);
    expect(await ReminderChoice.read(), isFalse);
    expect(await WhatsNewState.shouldShow(), isTrue);
    expect(await UpgradeNudgeState.isDismissed(), isFalse);
    expect(AnalyticsService.bufferedCount, 0);
    expect(photosOnDisk(), isFalse);
    expect(care.pets, isEmpty);
    expect(care.careEvents, isEmpty);
    expect(care.isConnected, isFalse);
    expect(reminders.cancelAllCalls, 1, reason: 'every reminder is cancelled');
    expect(widgetPayloads.last, contains('"hasPets":false'));
    expect(widgetPayloads.last, contains('"days":[]'));
  });

  test('caregiver: member-scoped delete, then local wipe', () async {
    final (care, adapter) = await owner({
      'DELETE /v1/account': [
        const Answer(200, {'deleted': true, 'scope': 'member'}),
      ],
    }, role: 'caregiver');
    expect(care.accountDeleteScope, AccountDeleteScope.member);
    expect(await care.deleteAccount(), isNull);
    expect(adapter.count('DELETE /v1/account'), 1);
    expect(AppLog.testRecords.last.fields['scope'], 'member');
    expect(care.pets, isEmpty);
  });

  test('offline: nothing is deleted anywhere', () async {
    final (care, _) = await owner({
      'DELETE /v1/account': [const Offline()],
    });
    await care.setPetPhoto('miso', sampleJpeg(48, 48));
    await care.flushPersist();

    final error = await care.deleteAccount();
    expect(error, contains('nothing was deleted'));
    expect(care.pets, isNotEmpty);
    expect(care.isConnected, isTrue);
    expect(await HouseholdStore().read(), isNotNull);
    expect(photosOnDisk(), isTrue);
    expect(care.accountDeletePending, isFalse);
    final failed = AppLog.testRecords.lastWhere(
      (r) => r.name == 'account.delete_failed',
    );
    expect(failed.fields['kind'], 'offline');
  });

  test('timeout: unconfirmed → no wipe; retry gets 401 → wiped', () async {
    final (care, adapter) = await owner({
      'DELETE /v1/account': [
        const TimedOut(),
        const Answer(401, {'error': 'Sign in again to reach this household.'}),
      ],
    });
    expect(
      await care.deleteAccount(),
      "Couldn't confirm the delete — check your connection and try again.",
    );
    expect(care.pets, isNotEmpty);
    expect(
      AppLog.testRecords
          .lastWhere((r) => r.name == 'account.delete_failed')
          .fields['kind'],
      'timeout',
    );

    expect(await care.deleteAccount(), isNull); // safe retry
    expect(adapter.count('DELETE /v1/account'), 2);
    expect(care.pets, isEmpty);
    expect(AppLog.logged('account.delete_already_gone'), isTrue);
  });

  test('401 straight away: phone already gone → finish locally', () async {
    final (care, _) = await owner({
      'DELETE /v1/account': [
        const Answer(401, {
          'error': 'This phone is no longer in the household.',
        }),
      ],
    });
    expect(await care.deleteAccount(), isNull);
    expect(care.pets, isEmpty);
    expect(await HouseholdStore().read(), isNull);
  });

  test('double tap sends one request', () async {
    final (care, adapter) = await owner({
      'DELETE /v1/account': [
        const Answer(200, {'deleted': true, 'scope': 'household'}),
      ],
    });
    final results = await Future.wait([
      care.deleteAccount(),
      care.deleteAccount(),
    ]);
    expect(results, [null, null]);
    expect(adapter.count('DELETE /v1/account'), 1);
  });

  test(
    'solo phone (pending outbox, or no household) never calls the server',
    () async {
      final outbox = SyncOutbox();
      await outbox.enqueue(
        const SyncBatchOp(id: 'op-1', type: 'refill', payload: {'id': 'x'}),
      );
      final adapter = RouteAdapter({});
      final care = CareRepository(
        api: routeApi(adapter, token: null),
        store: HouseholdStore(),
        syncEngine: SyncEngine(outbox: outbox),
      );
      await care.addPet(name: 'Miso', species: Species.cat);
      expect(care.accountDeleteScope, AccountDeleteScope.local);
      expect(await care.deleteAccount(), isNull);
      expect(adapter.calls, isEmpty);
      expect(
        AppLog.testRecords
            .lastWhere((r) => r.name == 'account.deleted')
            .fields['scope'],
        'local',
      );
      // Reading again opens a fresh, empty database (the file was deleted).
      expect(await outbox.read(), isEmpty);

      // Nothing at all on the phone: still succeeds.
      expect(await CareRepository().deleteAccount(), isNull);
    },
  );

  test('app killed mid-delete: next launch finishes the wipe', () async {
    final (care, adapter) = await owner({
      'DELETE /v1/account': [
        const Answer(401, {'error': 'Sign in again to reach this household.'}),
      ],
    });
    await care.flushPersist();
    // As if the app died after sending DELETE: flag set, nothing wiped.
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('account_delete_pending_v1', true);

    final relaunched = CareRepository(
      api: routeApi(adapter, token: null),
      store: HouseholdStore(),
    );
    await relaunched.restore();
    expect(relaunched.accountDeletePending, isTrue);
    expect(relaunched.isConnected, isTrue); // token restored from Keychain
    expect(await relaunched.deleteAccount(), isNull);
    expect(relaunched.pets, isEmpty);
    expect((await SharedPreferences.getInstance()).getKeys(), isEmpty);
  });

  test(
    'other member: owner deleted the household → clear message, data kept',
    () async {
      final (care, adapter) = await owner({}, role: 'caregiver');
      adapter.routes['GET /v1/household'] = [
        const Answer(401, {'error': 'Sign in again to reach this household.'}),
      ];
      await care.sync(force: true);
      expect(care.syncError, CareRepository.householdDeletedMessage);
      expect(AppLog.logged('household.deleted_by_owner'), isTrue);
      expect(care.isConnected, isFalse);
      expect(care.pets, isNotEmpty); // pets and doses stay on the phone
    },
  );

  test('owner whose token moved keeps the generic message', () async {
    final (care, adapter) = await owner({});
    adapter.routes['GET /v1/household'] = [
      const Answer(401, {'error': 'Sign in again to reach this household.'}),
    ];
    await care.sync(force: true);
    expect(care.syncError, isNot(CareRepository.householdDeletedMessage));
    expect(AppLog.logged('household.deleted_by_owner'), isFalse);
  });

  test(
    'explicit "no longer exists" message reads as deleted for anyone',
    () async {
      final (care, adapter) = await owner({});
      adapter.routes['GET /v1/household'] = [
        const Answer(401, {'error': 'This household no longer exists.'}),
      ];
      await care.sync(force: true);
      expect(care.syncError, CareRepository.householdDeletedMessage);
    },
  );

  testWidgets('owner sees the household-wide warning with pet names', (
    tester,
  ) async {
    final api = routeApi(RouteAdapter({}));
    final care = sampleCare(api: api);
    api.token = 'house-token'; // sample data starts solo; link it
    expect(care.accountDeleteScope, AccountDeleteScope.household);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: care),
          ChangeNotifierProvider(create: (_) => OnboardingViewModel()),
        ],
        child: const MaterialApp(home: SettingsScreen()),
      ),
    );
    await tester.pump();
    await tester.scrollUntilVisible(
      find.text('Delete account'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Delete account'));
    await tester.pumpAndSettle();
    expect(find.text('Delete your account and household?'), findsOneWidget);
    expect(find.textContaining('Miso and Juniper'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Delete your account and household?'), findsNothing);
  });

  testWidgets('slow delete: busy, then "still working", then a clear error', (
    tester,
  ) async {
    final gate = Completer<void>();
    final api = HouseholdApi(
      Uri.parse('https://example.test'),
      dio: Dio()..httpClientAdapter = _GatedAdapter(gate),
    );
    final care = sampleCare(api: api);
    api.token = 'house-token';
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: care),
          ChangeNotifierProvider(create: (_) => OnboardingViewModel()),
        ],
        child: const MaterialApp(home: SettingsScreen()),
      ),
    );
    await tester.pump();
    await tester.scrollUntilVisible(
      find.text('Delete account'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Delete account'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pump();
    expect(find.text('Deleting…'), findsOneWidget);
    expect(find.textContaining('Still working'), findsNothing);

    await tester.pump(const Duration(seconds: 6));
    expect(
      find.textContaining('Still working — slow connection'),
      findsOneWidget,
    );
    // Tapping outside or back does nothing while busy.
    await tester.tapAt(const Offset(5, 5));
    await tester.pump();
    expect(find.text('Deleting…'), findsOneWidget);

    gate.complete(); // the request now times out
    await tester.pumpAndSettle();
    expect(
      find.text(
        "Couldn't confirm the delete — check your connection and try again.",
      ),
      findsOneWidget,
    );
    expect(find.text('Try again'), findsOneWidget);
    expect(care.pets, isNotEmpty); // nothing wiped
  });
}

/// Holds every request until [gate] completes, then fails it as a timeout.
class _GatedAdapter implements HttpClientAdapter {
  _GatedAdapter(this.gate);

  final Completer<void> gate;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    await gate.future;
    throw DioException.receiveTimeout(
      timeout: const Duration(seconds: 45),
      requestOptions: options,
    );
  }

  @override
  void close({bool force = false}) {}
}
