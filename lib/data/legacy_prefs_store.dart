import 'dart:convert';

import 'package:pawsitive_sync/core/logging/app_log.dart';
import 'package:pawsitive_sync/data/household_api.dart';
import 'package:pawsitive_sync/data/household_store.dart';
import 'package:pawsitive_sync/data/local_database.dart';
import 'package:pawsitive_sync/data/secure_tokens.dart';
import 'package:pawsitive_sync/data/sync_outbox.dart';
import 'package:pawsitive_sync/domain/models.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

/// The pre-SQLite format: the whole household, the care events and the sync
/// outbox as three JSON strings in shared preferences.
///
/// Two jobs:
/// - [migrateInto] moves them into [LocalDatabase] once, on the first launch
///   after the update.
/// - The read/write helpers keep the app working on the old data when the
///   database can't be used this run (migration failed, disk full). The
///   next launch retries the migration, so nothing written meanwhile is lost.
abstract final class LegacyPrefsStore {
  static const householdKey = 'household_v2';
  static const eventsKey = 'care_events_v1';
  static const outboxKey = 'sync_outbox_v1';

  /// Set once the data lives in SQLite. If the database later can't be
  /// opened, the old keys must not be written again (the next launch would
  /// throw them away as migration leftovers), see [sqliteOwnsData].
  static const migratedFlagKey = 'store_sqlite_v1';

  /// `meta` row written in the same transaction as the migrated rows. Its
  /// presence means "never import the preferences blobs again".
  static const migratedMetaKey = 'legacy_migrated_at';

  /// True when an earlier run already moved the data into SQLite. The
  /// fallback then keeps changes in memory only rather than starting a
  /// second, diverging copy in preferences.
  static Future<bool> sqliteOwnsData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(migratedFlagKey) ?? false;
    } on Object {
      return false;
    }
  }

  /// Copies the old blobs into [db] in one transaction, checks the row
  /// counts, and only then deletes the old keys. Returns false (and leaves
  /// the old data untouched) on any failure; the caller then uses the old
  /// data for this run and the next launch tries again.
  ///
  /// Safe against being killed at any point: the rows and the
  /// [migratedMetaKey] marker commit together, and leftovers from a kill
  /// between commit and cleanup are removed on the next launch.
  static Future<bool> migrateInto(Database db) async {
    final watch = Stopwatch()..start();
    var stage = 'check';
    try {
      final done = await db.query(
        'meta',
        where: 'key = ?',
        whereArgs: [migratedMetaKey],
      );
      final prefs = await SharedPreferences.getInstance();
      if (done.isNotEmpty) {
        await _removeOldKeys(prefs);
        return true;
      }
      final rawHousehold = prefs.getString(householdKey);
      final rawEvents = prefs.getString(eventsKey);
      final rawOutbox = prefs.getString(outboxKey);
      if (rawHousehold == null && rawEvents == null && rawOutbox == null) {
        // Fresh install (or nothing saved yet): nothing to move.
        stage = 'fresh';
        await db.insert('meta', {
          'key': migratedMetaKey,
          'value': 'fresh',
        }, conflictAlgorithm: ConflictAlgorithm.replace);
        await prefs.setBool(migratedFlagKey, true);
        return true;
      }

      stage = 'parse';
      final json = _decodeHousehold(rawHousehold);
      final house = json == null ? null : parseHousehold(json, token: null);
      final events = readEventsJson(rawEvents);
      final outbox = readOutboxJson(rawOutbox);

      // A pre-Keychain build kept the token in the blob. It goes to secure
      // storage first; if that fails the old blob (and its token) stays.
      final legacyToken = json?['token'];
      if (legacyToken is String && legacyToken.isNotEmpty) {
        stage = 'token';
        await SecureTokens.write(SecureTokens.householdKey, legacyToken);
        AppLog.event('store.token_migrated');
      }

      stage = 'write';
      final counts = await db.transaction((txn) async {
        final batch = txn.batch();
        if (house != null) {
          for (final entry in metaRows(house).entries) {
            batch.insert('meta', {
              'key': entry.key,
              'value': entry.value,
            }, conflictAlgorithm: ConflictAlgorithm.replace);
          }
          for (final (i, m) in house.members.indexed) {
            batch.insert(
              'members',
              LocalRows.member(m, i),
              conflictAlgorithm: ConflictAlgorithm.replace,
            );
          }
          for (final (i, pet) in house.pets.indexed) {
            batch.insert(
              'pets',
              LocalRows.pet(pet, i),
              conflictAlgorithm: ConflictAlgorithm.replace,
            );
          }
          final active = {for (final m in house.medications) m.id};
          for (final (i, m) in house.medications.indexed) {
            batch.insert(
              'medications',
              LocalRows.medication(m, i),
              conflictAlgorithm: ConflictAlgorithm.replace,
            );
          }
          for (final (i, m) in house.archivedMedications.indexed) {
            if (active.contains(m.id)) continue; // re-added since: active wins
            batch.insert(
              'medications',
              LocalRows.medication(m, i),
              conflictAlgorithm: ConflictAlgorithm.replace,
            );
          }
          // Saved newest first; seq keeps that order within the same minute.
          final n = house.logs.length;
          for (final (i, log) in house.logs.indexed) {
            batch.insert(
              'dose_logs',
              LocalRows.log(log, n - i),
              conflictAlgorithm: ConflictAlgorithm.replace,
            );
          }
        }
        for (final (i, event) in events.indexed) {
          batch.insert(
            'care_events',
            LocalRows.careEvent(event, i),
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
        for (final op in outbox) {
          batch.insert('outbox', {
            'id': op.id,
            'type': op.type,
            'payload': jsonEncode(op.payload),
          }, conflictAlgorithm: ConflictAlgorithm.replace);
        }
        batch.insert('meta', {
          'key': migratedMetaKey,
          'value': DateTime.now().toUtc().toIso8601String(),
        }, conflictAlgorithm: ConflictAlgorithm.replace);
        await batch.commit(noResult: true);

        // Duplicate ids collapse to one row, so compare distinct ids.
        final expected = {
          'members': {...?house?.members.map((m) => m.id)}.length,
          'pets': {...?house?.pets.map((p) => p.id)}.length,
          'medications': {
            ...?house?.medications.map((m) => m.id),
            ...?house?.archivedMedications.map((m) => m.id),
          }.length,
          'dose_logs': {...?house?.logs.map((l) => l.id)}.length,
          'care_events': {...events.map((e) => e.id)}.length,
          'outbox': {...outbox.map((o) => o.id)}.length,
        };
        for (final entry in expected.entries) {
          final rows = Sqflite.firstIntValue(
            await txn.rawQuery('SELECT count(*) FROM ${entry.key}'),
          );
          if (rows != entry.value) {
            // Throwing rolls the whole migration back.
            throw StateError(
              'migrate ${entry.key}: wrote $rows of ${entry.value}',
            );
          }
        }
        return expected;
      });

      stage = 'cleanup';
      // From here the data is safe in SQLite; a failure below only leaves
      // leftovers that the next launch removes.
      try {
        await prefs.setBool(migratedFlagKey, true);
        await _removeOldKeys(prefs);
      } on Object catch (error, stack) {
        AppLog.error('store.migrate_cleanup_failed', error, stack);
      }
      AppLog.event('store.migrated', {
        'pets': counts['pets'],
        'logs': counts['dose_logs'],
        'events': counts['care_events'],
        'outbox': counts['outbox'],
        'ms': watch.elapsedMilliseconds,
      });
      return true;
    } on Object catch (error, stack) {
      AppLog.error('store.migrate_failed', error, stack, {'stage': stage});
      return false;
    }
  }

  static Future<void> _removeOldKeys(SharedPreferences prefs) async {
    for (final key in const [householdKey, eventsKey, outboxKey]) {
      if (prefs.containsKey(key)) await prefs.remove(key);
    }
  }

  /// The household blob as JSON, or null when absent or unreadable (logged
  /// as `store.household_corrupt`; there is nothing left to recover).
  static Map<String, dynamic>? _decodeHousehold(String? raw) {
    if (raw == null) return null;
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } on Object catch (error, stack) {
      AppLog.error('store.household_corrupt', error, stack, {
        'bytes': raw.length,
      });
      return null;
    }
  }

  /// Old-format household JSON → [StoredHousehold]. Returns null (logged)
  /// when the shape is wrong.
  static StoredHousehold? parseHousehold(
    Map<String, dynamic> json, {
    required String? token,
  }) {
    try {
      List<T> list<T>(String key, T Function(Map<String, dynamic>) map) => [
        for (final item in json[key] as List? ?? const [])
          if (item is Map<String, dynamic>) map(item),
      ];
      return StoredHousehold(
        householdId: json['householdId'] as String? ?? '',
        token: token,
        memberId: json['memberId'] as String? ?? 'you',
        inviteCode: json['inviteCode'] as String? ?? '',
        isPro: json['isPro'] == true,
        plan: json['plan'] == 'monthly'
            ? BillingPlan.monthly
            : BillingPlan.yearly,
        members: list('members', memberFromJson),
        pets: list('pets', petFromJson),
        medications: list('medications', medicationFromJson),
        logs: list('logs', doseRecordFromJson),
        // Older builds kept removed medicines without a stop time; the end
        // day they were given at removal is the best stand-in.
        archivedMedications: [
          for (final m in list('archivedMedications', medicationFromJson))
            m.isArchived ? m : m.copyWith(archivedAt: m.endDay),
        ],
      );
    } on Object catch (error, stack) {
      AppLog.error('store.household_corrupt', error, stack);
      return null;
    }
  }

  /// `meta` rows for the household fields that aren't lists.
  static Map<String, String> metaRows(StoredHousehold house) => {
    'saved': '1',
    'household_id': house.householdId,
    'member_id': house.memberId,
    'invite_code': house.inviteCode,
    'is_pro': house.isPro ? '1' : '0',
    'plan': house.plan.name,
  };

  static List<CareEvent> readEventsJson(String? raw) {
    if (raw == null) return const [];
    try {
      return [
        for (final item in jsonDecode(raw) as List)
          if (item is Map<String, dynamic>) CareEvent.fromJson(item),
      ];
    } on Object catch (error, stack) {
      AppLog.error('store.events_corrupt', error, stack);
      return const [];
    }
  }

  static List<SyncBatchOp> readOutboxJson(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    try {
      return [
        for (final item in jsonDecode(raw) as List)
          if (item is Map<String, dynamic>) SyncBatchOp.fromJson(item),
      ];
    } on Object catch (error, stack) {
      // Corrupt queue: logged so a lost offline change is never silent.
      AppLog.error('sync.outbox.read_failed', error, stack, {
        'bytes': raw.length,
      });
      return const [];
    }
  }

  // ---------------------------------------------------------------------------
  // Fallback for a run where the database can't be used. Same format and
  // behaviour as before the move to SQLite.

  /// The saved household JSON, or null. A corrupt blob is removed (logged),
  /// as the old store did.
  static Future<Map<String, dynamic>?> readHouseholdJson() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(householdKey);
    final json = _decodeHousehold(raw);
    if (raw != null && json == null) await prefs.remove(householdKey);
    return json;
  }

  static Future<void> writeHousehold(StoredHousehold house) async {
    if (await sqliteOwnsData()) {
      _memoryOnly('household');
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      householdKey,
      jsonEncode({
        'householdId': house.householdId,
        'memberId': house.memberId,
        'inviteCode': house.inviteCode,
        'isPro': house.isPro,
        'plan': house.plan.name,
        'members': [for (final member in house.members) member.toJson()],
        'pets': [for (final pet in house.pets) pet.toStoreJson()],
        'medications': [for (final item in house.medications) item.toJson()],
        'archivedMedications': [
          for (final item in house.archivedMedications)
            {...item.toJson(), 'archivedAt': ?item.archivedAt},
        ],
        // The old format's cap: one string has to fit in preferences.
        'logs': [for (final log in house.logs.take(3000)) log.toJson()],
      }),
    );
  }

  /// Rewrites the household blob without its plain-text token.
  static Future<void> rewriteHouseholdJson(Map<String, dynamic> json) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(householdKey, jsonEncode(json));
  }

  static Future<void> clearHousehold() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(householdKey);
  }

  static Future<List<CareEvent>> readEvents() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(eventsKey);
    final events = readEventsJson(raw);
    if (raw != null && events.isEmpty && raw != '[]') {
      await prefs.remove(eventsKey);
    }
    return events;
  }

  static Future<void> writeEvents(List<CareEvent> events) async {
    if (await sqliteOwnsData()) {
      _memoryOnly('care_events');
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      eventsKey,
      jsonEncode([for (final event in events) event.toJson()]),
    );
  }

  static Future<void> clearEvents() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(eventsKey);
  }

  static Future<List<SyncBatchOp>> readOutbox() async {
    final prefs = await SharedPreferences.getInstance();
    return [...readOutboxJson(prefs.getString(outboxKey))];
  }

  static Future<void> writeOutbox(List<SyncBatchOp> items) async {
    if (await sqliteOwnsData()) {
      _memoryOnly('outbox');
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      outboxKey,
      jsonEncode([for (final item in items) item.toJson()]),
    );
  }

  static Future<void> clearOutbox() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(outboxKey);
  }

  static void _memoryOnly(String table) {
    AppLog.event('store.write_failed', {
      'table': table,
      'reason': 'database_unavailable',
    });
  }
}
