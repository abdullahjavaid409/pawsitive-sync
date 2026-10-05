import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pawsitive_sync/core/logging/app_log.dart';
import 'package:pawsitive_sync/data/care_events_store.dart';
import 'package:pawsitive_sync/data/care_repository.dart';
import 'package:pawsitive_sync/data/household_store.dart';
import 'package:pawsitive_sync/data/legacy_prefs_store.dart';
import 'package:pawsitive_sync/data/local_database.dart';
import 'package:pawsitive_sync/data/secure_tokens.dart';
import 'package:pawsitive_sync/data/sync_outbox.dart';
import 'package:pawsitive_sync/domain/models.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart' show Sqflite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'test_log_helpers.dart';

/// Blobs written by the pre-SQLite build’s own stores (household_store,
/// care_events_store, sync_outbox at d92aa9c), so the upgrade is tested
/// against the exact bytes phones have saved today.
final Map<String, dynamic> _fixture = jsonDecode(
  File('test/fixtures/legacy_prefs_v2.json').readAsStringSync(),
) as Map<String, dynamic>;

Map<String, Object> _oldPrefs({bool preKeychain = false}) => {
  LegacyPrefsStore.householdKey:
      _fixture[preKeychain ? 'household_v2_pre_keychain' : 'household_v2']
          as String,
  LegacyPrefsStore.eventsKey: _fixture['care_events_v1'] as String,
  LegacyPrefsStore.outboxKey: _fixture['sync_outbox_v1'] as String,
};

/// The old household blob with [count] logs (the old store saved up to 3,000).
String _bigHouseholdBlob(int count) {
  final json =
      jsonDecode(_fixture['household_v2'] as String) as Map<String, dynamic>;
  json['logs'] = [
    for (var i = 0; i < count; i++)
      {
        'id': 'log-big-$i',
        'medicationId': 'med-111111',
        'part': 'morning',
        'day': '2026-0${1 + i % 9}-${(10 + i % 18)}',
        'memberId': 'mem_owner',
        'outcome': 'given',
        'amount': '2 units',
        'timeLabel': '8:00 AM',
        'note': 'A note long enough to take some space on disk, $i',
      },
  ];
  return jsonEncode(json);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late String path;

  /// A database on a real file, as on a phone; [cap] limits it to that many
  /// 4 KB pages, which SQLite reports exactly like a full disk.
  LocalDatabase fileDb({int? cap}) {
    final db = LocalDatabase(
      factory: databaseFactoryFfiNoIsolate,
      path: () async => path,
    );
    if (cap != null) {
      db.debugOnOpen = (d) async {
        await d.rawQuery('PRAGMA max_page_count = $cap');
      };
    }
    return LocalDatabase.shared = db;
  }

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppLog.enableTestCapture();
    dir = Directory.systemTemp.createTempSync('pawsitive_db_');
    path = '${dir.path}/${LocalDatabase.fileName}';
  });
  tearDown(() async {
    await LocalDatabase.shared.close();
    AppLog.disableTestCapture();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  group('Upgrade from the preferences blobs', () {
    test('moves today’s saved format into SQLite and removes it', () async {
      SharedPreferences.setMockInitialValues(_oldPrefs());
      final oldJson = jsonDecode(
        _fixture['household_v2'] as String,
      ) as Map<String, dynamic>;

      final house = (await HouseholdStore().read())!;
      expect(house.householdId, 'hh_7f3a');
      expect(house.memberId, 'mem_owner');
      expect(house.inviteCode, 'KQ7M2P');
      expect(house.isPro, isTrue);
      expect(house.plan, BillingPlan.monthly);
      expect(house.members.map((m) => m.id), ['mem_owner', 'mem_sara', 'dan']);
      expect(house.members.last.joined, isFalse);
      expect(house.pets.map((p) => p.name), ['Miso', 'Juniper']);
      final miso = house.pets.first;
      expect(miso.conditions, ['Diabetes', 'Kidney disease']);
      expect(miso.photoKey, 'households/hh_7f3a/pets/pet-a1b2c3/9f.jpg');
      expect(miso.photoSync, PhotoSync.upload);
      expect(miso.photoVersion, 1759550000);
      expect(house.pets.last.weightKg, 18.25);
      expect(house.medications.map((m) => m.name), ['Insulin', 'Carprofen']);
      expect(house.medications.last.endDay, '2026-10-20');
      expect(house.medications.last.dosesLeft, 4);
      // The old store kept removed medicines without a stop time.
      final stopped = house.archivedMedications.single;
      expect(stopped.name, 'Antibiotic');
      expect(stopped.archivedAt, '2026-09-14');
      expect(stopped.historyName, 'Antibiotic (stopped Sep 14)');
      // Every log, same ids, same newest-first order within a day.
      final oldLogs = (oldJson['logs'] as List).cast<Map<String, dynamic>>();
      expect(house.logs, hasLength(oldLogs.length));
      expect(
        house.logs.map((l) => l.id).toSet(),
        oldLogs.map((l) => l['id']).toSet(),
      );
      final noted = house.logs.firstWhere((l) => l.id == 'log-0006');
      expect(noted.note, 'Partial dose');
      expect(
        jsonEncode(noted.toJson()),
        jsonEncode(oldLogs.firstWhere((l) => l['id'] == 'log-0006')),
      );

      final events = await CareEventsStore().read();
      expect(events.map((e) => e.title), ['Rabies booster', 'Checkup']);
      expect(events.last.note, 'Bring stool sample');
      final ops = await SyncOutbox().read();
      expect(ops.map((o) => o.id), ['op-1', 'op-2']);
      expect(ops.first.payload['medicationId'], 'med-111111');

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(LegacyPrefsStore.householdKey), isNull);
      expect(prefs.getString(LegacyPrefsStore.eventsKey), isNull);
      expect(prefs.getString(LegacyPrefsStore.outboxKey), isNull);
      expectLogged(
        'store.migrated',
        fields: {'pets': 2, 'logs': oldLogs.length, 'events': 2, 'outbox': 2},
      );
      expectLogged('store.opened');
    });

    test('a pre-Keychain token goes to secure storage, never SQLite', () async {
      SharedPreferences.setMockInitialValues(_oldPrefs(preKeychain: true));
      final db = fileDb();
      final house = (await HouseholdStore().read())!;
      expect(house.token, 'legacy-token');
      expect(
        await SecureTokens.read(SecureTokens.householdKey),
        'legacy-token',
      );
      expectLogged('store.token_migrated');
      await db.close();
      expect(File(path).readAsBytesSync(), isNot(_contains('legacy-token')));
    });

    test('fresh install skips it and leaves nothing behind', () async {
      expect(await HouseholdStore().read(), isNull);
      expectNotLogged('store.migrated');
      expectNotLogged('store.migrate_failed');
      expectLogged('store.opened');
    });

    test('a corrupt household blob is logged; the rest still moves', () async {
      SharedPreferences.setMockInitialValues({
        ..._oldPrefs(),
        LegacyPrefsStore.householdKey: '{"pets": [ not json',
      });
      expect(await HouseholdStore().read(), isNull);
      expectLogged('store.household_corrupt');
      expect(await CareEventsStore().read(), hasLength(2));
      expect(await SyncOutbox().read(), hasLength(2));
      expectLogged('store.migrated', fields: {'pets': 0, 'events': 2});
    });

    test('disk full mid-migration: old data kept and used, retried next '
        'launch, nothing lost', () async {
      SharedPreferences.setMockInitialValues({
        ..._oldPrefs(),
        LegacyPrefsStore.householdKey: _bigHouseholdBlob(3000),
      });
      // Room for the empty schema, not for 3,000 logs.
      fileDb(cap: 24);
      final store = HouseholdStore();
      final first = (await store.read())!;
      expectLogged('store.migrate_failed', fields: {'stage': 'write'});
      expectNotLogged('store.migrated');
      // This run keeps working on the old blob…
      expect(first.logs, hasLength(3000));
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(LegacyPrefsStore.householdKey), isNotNull);
      // …and keeps saving to it, so a change made now survives the retry.
      await store.write(
        StoredHousehold(
          householdId: first.householdId,
          token: first.token,
          memberId: first.memberId,
          inviteCode: first.inviteCode,
          isPro: first.isPro,
          plan: first.plan,
          members: first.members,
          pets: first.pets,
          medications: first.medications,
          archivedMedications: first.archivedMedications,
          logs: [
            DoseRecord(
              id: 'log-while-full',
              medicationId: 'med-111111',
              part: DayPart.evening,
              day: '2026-10-03',
              memberId: 'mem_owner',
              outcome: LogOutcome.given,
              amount: '',
              timeLabel: '8:01 PM',
            ),
            ...first.logs.take(2999),
          ],
        ),
      );

      // Next launch, space freed.
      await LocalDatabase.shared.close();
      AppLog.testRecords.clear();
      fileDb();
      final second = (await HouseholdStore().read())!;
      expectLogged('store.migrated', fields: {'logs': 3000});
      expect(second.logs.first.id, 'log-while-full');
      expect(prefs.getString(LegacyPrefsStore.householdKey), isNull);
    });

    test('killed after the commit, before cleanup: leftovers are removed, '
        'never imported twice', () async {
      SharedPreferences.setMockInitialValues(_oldPrefs());
      fileDb();
      final store = HouseholdStore();
      final house = (await store.read())!;
      // A change saved in SQLite after the migration…
      await store.write(
        StoredHousehold(
          householdId: house.householdId,
          token: house.token,
          memberId: house.memberId,
          inviteCode: house.inviteCode,
          isPro: house.isPro,
          plan: house.plan,
          members: house.members,
          pets: [house.pets.first],
          medications: house.medications,
          logs: house.logs,
        ),
      );
      await LocalDatabase.shared.close();
      // …then old keys reappear, as if the app died before deleting them.
      SharedPreferences.setMockInitialValues(_oldPrefs());
      AppLog.testRecords.clear();
      fileDb();
      final again = (await HouseholdStore().read())!;
      expect(again.pets, hasLength(1), reason: 'SQLite stays the truth');
      expectNotLogged('store.migrated');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(LegacyPrefsStore.householdKey), isNull);
    });

    test('interrupted mid-transaction rolls back completely', () async {
      SharedPreferences.setMockInitialValues({
        ..._oldPrefs(),
        LegacyPrefsStore.householdKey: _bigHouseholdBlob(3000),
      });
      fileDb(cap: 24);
      await HouseholdStore().read();
      await LocalDatabase.shared.close();
      // No partial rows: the file holds the empty schema only.
      final raw = await databaseFactoryFfiNoIsolate.openDatabase(path);
      for (final table in ['meta', 'pets', 'dose_logs', 'outbox']) {
        expect(
          Sqflite.firstIntValue(
            await raw.rawQuery('SELECT count(*) FROM $table'),
          ),
          0,
          reason: table,
        );
      }
      await raw.close();
    });
  });

  group('Per-record writes', () {
    StoredHousehold house(List<DoseRecord> logs, {Set<String>? deleted}) =>
        StoredHousehold(
          token: null,
          memberId: 'you',
          inviteCode: '',
          isPro: false,
          plan: BillingPlan.yearly,
          members: const [],
          pets: const [
            Pet(
              id: 'p',
              name: 'Miso',
              species: Species.cat,
              ageYears: 1,
              breed: '',
              sex: '',
              conditions: [],
              weightKg: 4,
              onTimePercent: 0,
              dailyMeds: 0,
            ),
          ],
          medications: const [],
          logs: logs,
          deletedLogIds: deleted ?? const {},
        );
    DoseRecord log(String id, String day, [String time = '8:00 AM']) =>
        DoseRecord(
          id: id,
          medicationId: 'm',
          part: DayPart.morning,
          day: day,
          memberId: 'you',
          outcome: LogOutcome.given,
          amount: '',
          timeLabel: time,
        );

    test('no cap: 5,000 logs saved, only the recent window loaded', () async {
      final logs = [
        for (var i = 0; i < 5000; i++)
          log('l$i', i < 10 ? '2026-10-03' : '2025-0${1 + i % 9}-10'),
      ];
      await HouseholdStore().write(house(logs));
      final recent = await HouseholdStore().read(sinceDay: '2026-07-01');
      expect(recent!.logs, hasLength(10));
      expect(await HouseholdStore().readLogs(), hasLength(5000));
      expect(
        await HouseholdStore().readLogs(beforeDay: '2026-07-01', limit: 7),
        hasLength(7),
      );
    });

    test('same-minute logs keep their order across a restart', () async {
      final store = HouseholdStore();
      await store.write(house([log('a', '2026-10-03')]));
      await store.write(
        house([log('b', '2026-10-03'), log('a', '2026-10-03')]),
      );
      await store.write(
        house([
          log('c', '2026-10-03', '9:15 PM'),
          log('b', '2026-10-03'),
          log('a', '2026-10-03'),
        ]),
      );
      final back = await HouseholdStore().read();
      expect(back!.logs.map((l) => l.id), ['c', 'b', 'a']);
    });

    test('logs are deleted only when asked, never for being out of '
        'memory', () async {
      final store = HouseholdStore();
      await store.write(
        house([log('new', '2026-10-03'), log('old', '2025-01-01')]),
      );
      await store.write(house([log('new', '2026-10-03')]));
      expect(await store.readLogs(), hasLength(2));
      await store.write(house([log('new', '2026-10-03')], deleted: {'old'}));
      expect((await store.readLogs()).map((l) => l.id), ['new']);
    });

    test('disk full on a dose write: logged with the table, nothing '
        'half-saved, retried by the next save', () async {
      final db = fileDb();
      final store = HouseholdStore();
      await store.write(house([log('a', '2026-10-03')]));
      final open = (await db.open())!;
      final pages = Sqflite.firstIntValue(
        await open.rawQuery('PRAGMA page_count'),
      )!;
      await open.rawQuery('PRAGMA max_page_count = $pages');
      final many = [
        for (var i = 0; i < 2000; i++)
          DoseRecord(
            id: 'x$i',
            medicationId: 'm',
            part: DayPart.morning,
            day: '2026-10-03',
            memberId: 'you',
            outcome: LogOutcome.given,
            amount: '',
            timeLabel: '8:00 AM',
            note: 'note $i ' * 10,
          ),
        log('a', '2026-10-03'),
      ];
      await expectLater(store.write(house(many)), throwsA(anything));
      expectLogged('store.write_failed', fields: {'table': 'dose_logs'});
      expect(await store.readLogs(), hasLength(1), reason: 'rolled back');

      await open.rawQuery('PRAGMA max_page_count = 100000');
      await store.write(house(many)); // same rows, now they fit
      expect(await store.readLogs(), hasLength(2001));
    });

    test('a damaged database file is set aside and a fresh one used', () async {
      File(path).writeAsStringSync('this is not a database' * 200);
      fileDb();
      expect(await HouseholdStore().read(), isNull);
      expectLogged('store.corrupt_moved');
      expect(File('$path.corrupt').existsSync(), isTrue);
      await HouseholdStore().write(house([log('a', '2026-10-03')]));
      expect(await HouseholdStore().readLogs(), hasLength(1));
    });

    test('a bad row is skipped, not the whole household', () async {
      final db = fileDb();
      await HouseholdStore().write(house([log('a', '2026-10-03')]));
      final open = (await db.open())!;
      await open.update('pets', {'conditions': '{broken'});
      final back = await HouseholdStore().read();
      expect(back!.pets, isEmpty);
      expect(back.logs, hasLength(1));
      expectLogged('store.row_corrupt', fields: {'table': 'pets'});
    });

    test('database unavailable after the move: changes go to recovery '
        'keys and are merged back on the next launch', () async {
      final saved = fileDb();
      final first = HouseholdStore();
      await first.write(house([log('kept', '2026-10-02')]));
      await saved.close();
      SharedPreferences.setMockInitialValues({
        LegacyPrefsStore.migratedFlagKey: true,
      });
      // The file is there but can’t be opened this run (a directory takes
      // its path); retries are quick in tests.
      LocalDatabase.openRetryDelays = const [Duration.zero];
      addTearDown(
        () => LocalDatabase.openRetryDelays = const [
          Duration(milliseconds: 150),
          Duration(milliseconds: 600),
        ],
      );
      final real = File(path).renameSync('$path.real');
      Directory(path).createSync();
      fileDb();
      final down = HouseholdStore();
      expect(await down.read(), isNull);
      await down.write(house([log('while-down', '2026-10-03')]));
      final outbox = SyncOutbox();
      await outbox.enqueue(
        const SyncBatchOp(id: 'op', type: 'refill', payload: {'id': 'm'}),
      );
      expectLogged('store.open_retry');
      expectLogged('store.open_failed');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(LegacyPrefsStore.householdKey), isNull);
      expect(prefs.getString(LegacyPrefsStore.recoveryHouseholdKey), isNotNull);
      expect(await SyncOutbox().read(), hasLength(1), reason: 'kept on disk');

      // Next launch: the database opens again.
      await LocalDatabase.shared.close();
      Directory(path).deleteSync();
      real.renameSync(path);
      fileDb();
      final logs = await HouseholdStore().readLogs();
      expect(logs.map((l) => l.id), containsAll(['kept', 'while-down']));
      expect(await SyncOutbox().read(), hasLength(1));
      expectLogged('store.recovered', fields: {'logs': 1, 'outbox': 1});
      expect(prefs.getString(LegacyPrefsStore.recoveryHouseholdKey), isNull);
    });

    test('a day keeps the exact order the app had, also after a server '
        'snapshot reorders it', () async {
      final store = HouseholdStore();
      await store.write(
        house([
          log('b', '2026-10-03', '9:00 AM'),
          log('a', '2026-10-03', '8:00 AM'),
        ]),
      );
      // The server lists its own order (insert time), not clock order; a
      // log for an earlier time that was synced later comes first.
      await store.write(
        house([
          log('late-sync', '2026-10-03', '7:00 AM'),
          log('b', '2026-10-03', '9:00 AM'),
          log('a', '2026-10-03', '8:00 AM'),
          log('y', '2026-10-02'),
        ]),
      );
      final back = await HouseholdStore().read();
      expect(back!.logs.map((l) => l.id), ['late-sync', 'b', 'a', 'y']);
      // Only today’s new log was written (others kept their place).
      expect(store.lastWriteRows, 2, reason: 'late-sync + y');
    });
  });

  test('launch can’t read the saved household: nothing is saved over it '
      'this run, logging still works', () async {
    final store = _UnreadableStore();
    final care = CareRepository(store: store);
    await care.restore();
    expectLogged('store.read_failed', fields: {'table': 'household'});
    expect(await care.addPet(name: 'Miso', species: Species.cat), isNotNull);
    await care.flushPersist();
    expect(store.writes, 0);
  });

  group('Account deletion', () {
    test('deletes the database file', () async {
      fileDb();
      final care = CareRepository(store: HouseholdStore());
      await care.addPet(name: 'Miso', species: Species.cat);
      await care.flushPersist();
      expect(File(path).existsSync(), isTrue);
      await care.wipeDevice();
      expect(File(path).existsSync(), isFalse);
      expect(
        AppLog.testRecords.where(
          (r) =>
              r.name == 'account.wipe_step_failed' &&
              r.fields['step'] == 'database',
        ),
        isEmpty,
      );
    });
  });
}

Matcher _contains(String text) => predicate<List<int>>(
  (bytes) => latin1.decode(bytes, allowInvalid: true).contains(text),
  'contains "$text"',
);

class _UnreadableStore extends HouseholdStore {
  int writes = 0;

  @override
  Future<StoredHousehold?> read({String? sinceDay}) async =>
      throw const FileSystemException('disk I/O error');

  @override
  Future<void> write(StoredHousehold house) async => writes++;
}
