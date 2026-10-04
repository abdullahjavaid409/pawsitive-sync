import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pawsitive_sync/core/logging/app_log.dart';
import 'package:pawsitive_sync/data/household_api.dart';
import 'package:pawsitive_sync/data/legacy_prefs_store.dart';
import 'package:pawsitive_sync/domain/models.dart';
import 'package:sqflite/sqflite.dart';

/// The phone's copy of the household in SQLite: one row per member, pet,
/// medicine, dose log, care event and queued sync op, so saving a dose
/// writes one row instead of re-encoding the whole history.
///
/// One connection per app run, shared by `HouseholdStore`, `CareEventsStore`
/// and `SyncOutbox`. The household token is never stored here (it lives in
/// `SecureTokens`).
///
/// [open] returns null when the database can't be used this run (old data
/// couldn't be migrated, disk full while creating it, …). Callers then fall
/// back to [LegacyPrefsStore] so the app keeps working on the old data.
class LocalDatabase {
  LocalDatabase({this._factory, Future<String> Function()? path})
    : _path = path ?? _defaultPath;

  /// The app's database. Tests swap it (see `flutter_test_config.dart`).
  static LocalDatabase shared = LocalDatabase();

  static const fileName = 'pawsitive.db';
  static const schemaVersion = 1;

  final DatabaseFactory? _factory;
  final Future<String> Function() _path;

  DatabaseFactory get _db => _factory ?? databaseFactory;

  Future<Database?>? _opening;

  /// Bumped whenever the file is closed or deleted, so stores drop row
  /// caches that describe a database that no longer exists.
  int get generation => _generation;
  int _generation = 0;

  /// Runs on the open connection before the schema/migration step. Tests use
  /// it to cap the file size (`PRAGMA max_page_count`) and simulate a full disk.
  @visibleForTesting
  Future<void> Function(Database db)? debugOnOpen;

  static Future<String> _defaultPath() async {
    // Application Support, not Documents: not visible in the Files app.
    final dir = await getApplicationSupportDirectory();
    return p.join(dir.path, fileName);
  }

  /// The open database, or null when this run must use the old preferences
  /// store. Opens (and migrates) once; concurrent callers share the result.
  Future<Database?> open() => _opening ??= _open();

  Future<Database?> _open() async {
    final watch = Stopwatch()..start();
    final String path;
    try {
      path = await _path();
    } on Object catch (error, stack) {
      AppLog.error('store.open_failed', error, stack, {'stage': 'path'});
      return null;
    }
    Database? db;
    try {
      db = await _openFile(path);
    } on DatabaseException catch (error, stack) {
      if (!_isCorrupt(error)) {
        AppLog.error('store.open_failed', error, stack, {'stage': 'open'});
        return null;
      }
      // A damaged file can't be repaired here. Keep it aside (support can
      // still look at it) and start a clean one; a shared household comes
      // back from the server on the next sync.
      AppLog.error('store.corrupt_moved', error, stack);
      try {
        await File(path).rename('$path.corrupt');
        db = await _openFile(path);
      } on Object catch (error, stack) {
        AppLog.error('store.open_failed', error, stack, {'stage': 'reopen'});
        return null;
      }
    } on Object catch (error, stack) {
      AppLog.error('store.open_failed', error, stack, {'stage': 'open'});
      return null;
    }
    final migrated = await LegacyPrefsStore.migrateInto(db);
    if (!migrated) {
      await db.close();
      return null;
    }
    AppLog.event('store.opened', {'ms': watch.elapsedMilliseconds});
    return db;
  }

  Future<Database> _openFile(String path) async {
    final db = await _db.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: schemaVersion,
        onConfigure: (db) async {
          await debugOnOpen?.call(db);
        },
        onCreate: (db, _) => _createSchema(db),
      ),
    );
    // Reading the schema forces SQLite to read the file header: a damaged
    // or foreign file fails here (SQLITE_NOTADB) instead of on a later save.
    await db.rawQuery('SELECT count(*) FROM sqlite_master');
    return db;
  }

  static bool _isCorrupt(DatabaseException error) {
    final code = error.getResultCode();
    // SQLITE_CORRUPT (11) / SQLITE_NOTADB (26), also matched by text because
    // the result code isn't reported on every platform.
    return code == 11 ||
        code == 26 ||
        '$error'.contains('malformed') ||
        '$error'.contains('not a database');
  }

  static Future<void> _createSchema(Database db) async {
    final batch = db.batch()
      ..execute('CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT NOT NULL)')
      ..execute(
        '''
        CREATE TABLE members (
          id TEXT PRIMARY KEY, position INTEGER NOT NULL, name TEXT NOT NULL,
          role TEXT NOT NULL, joined INTEGER NOT NULL, is_you INTEGER NOT NULL)''',
      )
      ..execute('''
        CREATE TABLE pets (
          id TEXT PRIMARY KEY, position INTEGER NOT NULL, name TEXT NOT NULL,
          species TEXT NOT NULL, age_years INTEGER NOT NULL,
          weight_kg REAL NOT NULL, breed TEXT NOT NULL, sex TEXT NOT NULL,
          conditions TEXT NOT NULL, photo_key TEXT,
          photo_version INTEGER NOT NULL, photo_sync TEXT NOT NULL)''')
      ..execute('''
        CREATE TABLE medications (
          id TEXT PRIMARY KEY, position INTEGER NOT NULL, pet_id TEXT NOT NULL,
          name TEXT NOT NULL, amount TEXT NOT NULL, parts TEXT NOT NULL,
          supply_total INTEGER NOT NULL, doses_left INTEGER NOT NULL,
          start_day TEXT NOT NULL, end_day TEXT NOT NULL,
          archived INTEGER NOT NULL, archived_at TEXT)''')
      ..execute('''
        CREATE TABLE dose_logs (
          id TEXT PRIMARY KEY, medication_id TEXT NOT NULL, part TEXT NOT NULL,
          day TEXT NOT NULL, member_id TEXT NOT NULL, outcome TEXT NOT NULL,
          amount TEXT NOT NULL, time_label TEXT NOT NULL, note TEXT,
          minute INTEGER NOT NULL, seq INTEGER NOT NULL)''')
      ..execute('CREATE INDEX dose_logs_day ON dose_logs (day)')
      ..execute(
        'CREATE INDEX dose_logs_medication ON dose_logs (medication_id, day)',
      )
      ..execute('''
        CREATE TABLE care_events (
          id TEXT PRIMARY KEY, position INTEGER NOT NULL, pet_id TEXT NOT NULL,
          title TEXT NOT NULL, kind TEXT NOT NULL, due_day TEXT NOT NULL,
          note TEXT NOT NULL)''')
      ..execute('''
        CREATE TABLE outbox (
          seq INTEGER PRIMARY KEY AUTOINCREMENT, id TEXT NOT NULL UNIQUE,
          type TEXT NOT NULL, payload TEXT NOT NULL)''');
    await batch.commit(noResult: true);
  }

  /// Closes the connection; the next [open] reopens it (tests: a relaunch).
  Future<void> close() async {
    final opening = _opening;
    _opening = null;
    _generation++;
    final db = await opening?.catchError((Object _) => null);
    await db?.close();
  }

  /// Deletes the database file (account deletion). Safe when it never
  /// existed; the next [open] starts empty.
  Future<void> deleteFile() async {
    await close();
    final path = await _path();
    await _db.deleteDatabase(path);
    // A damaged copy set aside by [open] is household data too.
    final corrupt = File('$path.corrupt');
    if (await corrupt.exists()) await corrupt.delete();
  }
}

/// Row ⇄ model mapping for the tables in [LocalDatabase]. Row → model goes
/// through the same parsers as server JSON, so defaults stay in one place.
abstract final class LocalRows {
  static Map<String, Object?> member(Member m, int position) => {
    'id': m.id,
    'position': position,
    'name': m.name,
    'role': m.role.name,
    'joined': m.joined ? 1 : 0,
    'is_you': m.isYou ? 1 : 0,
  };

  static Member toMember(Map<String, Object?> row) => memberFromJson({
    'id': row['id'],
    'name': row['name'],
    'role': row['role'],
    'joined': row['joined'] == 1,
    'isYou': row['is_you'] == 1,
  });

  static Map<String, Object?> pet(Pet pet, int position) => {
    'id': pet.id,
    'position': position,
    'name': pet.name,
    'species': pet.species.name,
    'age_years': pet.ageYears,
    'weight_kg': pet.weightKg,
    'breed': pet.breed,
    'sex': pet.sex,
    'conditions': jsonEncode(pet.conditions),
    'photo_key': pet.photoKey,
    'photo_version': pet.photoVersion,
    'photo_sync': pet.photoSync.name,
  };

  static Pet toPet(Map<String, Object?> row) => petFromJson({
    'id': row['id'],
    'name': row['name'],
    'species': row['species'],
    'ageYears': row['age_years'],
    'weightKg': row['weight_kg'],
    'breed': row['breed'],
    'sex': row['sex'],
    'conditions': jsonDecode('${row['conditions'] ?? '[]'}'),
    'photoKey': row['photo_key'],
    'photoVersion': row['photo_version'],
    'photoSync': row['photo_sync'],
  });

  static Map<String, Object?> medication(Medication m, int position) => {
    'id': m.id,
    'position': position,
    'pet_id': m.petId,
    'name': m.name,
    'amount': m.amount,
    'parts': [for (final part in m.parts) part.name].join(','),
    'supply_total': m.supplyTotal,
    'doses_left': m.dosesLeft,
    'start_day': m.startDay,
    'end_day': m.endDay,
    'archived': m.isArchived ? 1 : 0,
    'archived_at': m.archivedAt,
  };

  static Medication toMedication(Map<String, Object?> row) {
    final parts = '${row['parts'] ?? ''}';
    final parsed = medicationFromJson({
      'id': row['id'],
      'petId': row['pet_id'],
      'name': row['name'],
      'amount': row['amount'],
      'parts': parts.isEmpty ? const <String>[] : parts.split(','),
      'supplyTotal': row['supply_total'],
      'dosesLeft': row['doses_left'],
      'startDay': row['start_day'],
      'endDay': row['end_day'],
    });
    if (row['archived'] != 1) return parsed;
    return parsed.copyWith(archivedAt: '${row['archived_at'] ?? ''}');
  }

  /// [seq] orders logs saved in the same minute (newest = highest).
  static Map<String, Object?> log(DoseRecord log, int seq) => {
    'id': log.id,
    'medication_id': log.medicationId,
    'part': log.part.name,
    'day': log.day,
    'member_id': log.memberId,
    'outcome': log.outcome.name,
    'amount': log.amount,
    'time_label': log.timeLabel,
    'note': log.note,
    'minute': minuteOfDay(log.timeLabel),
    'seq': seq,
  };

  /// Built directly (no intermediate JSON map): launch reads thousands.
  static DoseRecord toLog(Map<String, Object?> row) => DoseRecord(
    id: row['id']! as String,
    medicationId: row['medication_id']! as String,
    part: _byName(DayPart.values, row['part'], DayPart.morning),
    day: row['day']! as String,
    memberId: row['member_id']! as String,
    outcome: _byName(LogOutcome.values, row['outcome'], LogOutcome.given),
    amount: row['amount'] as String? ?? '',
    timeLabel: row['time_label'] as String? ?? '',
    note: row['note'] as String?,
  );

  static T _byName<T extends Enum>(List<T> values, Object? name, T fallback) {
    for (final value in values) {
      if (value.name == name) return value;
    }
    return fallback;
  }

  static Map<String, Object?> careEvent(CareEvent event, int position) => {
    'id': event.id,
    'position': position,
    'pet_id': event.petId,
    'title': event.title,
    'kind': event.kind.name,
    'due_day': event.dueDay,
    'note': event.note,
  };

  static CareEvent toCareEvent(Map<String, Object?> row) => CareEvent.fromJson({
    'id': row['id'],
    'petId': row['pet_id'],
    'title': row['title'],
    'kind': row['kind'],
    'dueDay': row['due_day'],
    'note': row['note'],
  });

  static final _clock = RegExp(r'^\s*(\d{1,2}):(\d{2})\s*([AaPp][Mm])?');

  /// Minutes since midnight from "8:02 AM" / "20:02", or -1 when unreadable.
  /// Logs load newest first by (day, minute, seq), the order the app keeps
  /// them in memory.
  static int minuteOfDay(String label) {
    final match = _clock.firstMatch(label);
    if (match == null) return -1;
    var hour = int.parse(match[1]!);
    final minute = int.parse(match[2]!);
    final half = match[3]?.toUpperCase();
    if (half != null) {
      hour %= 12;
      if (half == 'PM') hour += 12;
    }
    if (hour > 23 || minute > 59) return -1;
    return hour * 60 + minute;
  }
}
