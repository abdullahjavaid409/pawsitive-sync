import 'package:flutter/foundation.dart' show mapEquals, visibleForTesting;
import 'package:pawsitive_sync/core/logging/app_log.dart';
import 'package:pawsitive_sync/data/legacy_prefs_store.dart';
import 'package:pawsitive_sync/data/local_database.dart';
import 'package:pawsitive_sync/data/secure_tokens.dart';
import 'package:pawsitive_sync/domain/models.dart';
import 'package:sqflite/sqflite.dart';

/// What this phone remembers about its household between launches.
class StoredHousehold {
  const StoredHousehold({
    required this.token,
    required this.memberId,
    required this.inviteCode,
    required this.isPro,
    required this.plan,
    required this.members,
    required this.pets,
    required this.medications,
    required this.logs,
    this.householdId = '',
    this.archivedMedications = const [],
    this.deletedLogIds = const {},
    this.replaceLogs = false,
    this.inviteExpiresAt,
  });

  /// When [inviteCode] stops working (owner only; null when unknown).
  final DateTime? inviteExpiresAt;

  final String householdId;
  final String? token;
  final String memberId;
  final String inviteCode;
  final bool isPro;
  final BillingPlan plan;
  final List<Member> members;
  final List<Pet> pets;
  final List<Medication> medications;

  /// Newest first. On [HouseholdStore.read], only the recent window; older
  /// logs stay on disk (see [HouseholdStore.readLogs]).
  final List<DoseRecord> logs;

  /// Stopped medicines (each with [Medication.archivedAt]), kept so their
  /// dose history keeps its real name.
  final List<Medication> archivedMedications;

  /// Logs to remove from disk on this write. Logs are never deleted just for
  /// being absent from [logs]: memory holds only a window of the history.
  final Set<String> deletedLogIds;

  /// Drop every saved log first (joined another household: the old one's
  /// history must not mix in), then save [logs].
  final bool replaceLogs;
}

/// Saves the household in [LocalDatabase], one row per record. The bearer
/// token is kept apart in [SecureTokens] (Keychain / Keystore) and never
/// written to the database or preferences.
///
/// [write] compares against what it last read or wrote and touches only the
/// rows that changed, in one transaction: logging a dose is one row insert
/// (plus the medicine's supply), however long the history is.
///
/// Use one store per database: the row cache assumes nothing else writes
/// these tables.
class HouseholdStore {
  HouseholdStore({this._database});

  final LocalDatabase? _database;
  LocalDatabase get _db => _database ?? LocalDatabase.shared;

  /// Days of history [read] loads into memory. Covers the longest report
  /// (90 days) with margin; older logs stay on disk.
  static const recentDays = 100;

  /// Last token known to be in secure storage, so a write touches the
  /// Keychain only when the token actually changed.
  String? _savedToken;

  /// False until secure storage answered once. A failed read must never be
  /// mistaken for "signed out" and wipe a good token on the next write.
  bool _tokenKnown = false;

  // Row cache: table → id → row, as last read from or committed to disk.
  // Rows are compared by value, so a model rebuilt with the same data (a
  // server snapshot) costs a comparison, not a write.
  final Map<String, Map<String, Map<String, Object?>>> _rows = {};
  Map<String, String> _meta = {};

  /// Log objects as last read/written. Models are immutable, so the same
  /// instance means the same row: a save skips building rows for the whole
  /// history and only looks at logs that are new or were replaced.
  final Map<String, DoseRecord> _logObjects = {};

  /// False until the small tables were read (or fully written) through this
  /// store; until then a write replaces them wholesale.
  bool _primed = false;
  int _generation = -1;

  /// Rows upserted or deleted by the last committed [write] (perf tests).
  @visibleForTesting
  int lastWriteRows = 0;

  void _syncGeneration() {
    if (_generation == _db.generation) return;
    _generation = _db.generation;
    _rows.clear();
    _logObjects.clear();
    _meta = {};
    _primed = false;
  }

  /// The saved household, or null when nothing is saved. [sinceDay]
  /// (YYYY-MM-DD) limits the logs loaded into memory; null loads them all.
  Future<StoredHousehold?> read({String? sinceDay}) async {
    final db = await _db.open();
    if (db == null) return _legacyRead();
    _syncGeneration();
    final metaRows = await db.query('meta');
    final meta = {
      for (final row in metaRows) '${row['key']}': '${row['value']}',
    };
    if (meta['saved'] != '1') {
      // Nothing saved (fresh install or reinstall). The iOS Keychain outlives
      // an uninstall, so drop any orphaned token from a previous install.
      await _writeToken(null, force: true);
      return null;
    }
    final members = await _readTable(db, 'members', LocalRows.toMember);
    final pets = await _readTable(db, 'pets', LocalRows.toPet);
    final allMeds = await _readTable(db, 'medications', LocalRows.toMedication);
    final logRows = await db.query(
      'dose_logs',
      where: sinceDay == null ? null : 'day >= ?',
      whereArgs: sinceDay == null ? null : [sinceDay],
      orderBy: 'day DESC, ord DESC',
    );
    final logs = _parseRows('dose_logs', logRows, LocalRows.toLog);
    _logObjects
      ..clear()
      ..addEntries([for (final log in logs) MapEntry(log.id, log)]);
    _meta = meta;
    _primed = true;
    final token = await _readToken();
    return StoredHousehold(
      householdId: meta['household_id'] ?? '',
      token: token,
      memberId: meta['member_id'] ?? 'you',
      inviteCode: meta['invite_code'] ?? '',
      inviteExpiresAt: DateTime.tryParse(meta['invite_expires_at'] ?? ''),
      isPro: meta['is_pro'] == '1',
      plan: meta['plan'] == 'monthly'
          ? BillingPlan.monthly
          : BillingPlan.yearly,
      members: members,
      pets: pets,
      medications: [
        for (final m in allMeds)
          if (!m.isArchived) m,
      ],
      archivedMedications: [
        for (final m in allMeds)
          if (m.isArchived) m,
      ],
      logs: logs,
    );
  }

  /// Logs on disk, newest first, with `fromDay <= day < beforeDay` (either
  /// bound optional), at most [limit]. For history outside the window
  /// [read] loads, e.g. the full history sent when a household is shared.
  ///
  /// [remember]: the caller adds these logs to the list it saves, so the
  /// store treats them as already on disk (no rewrite on the next save).
  Future<List<DoseRecord>> readLogs({
    String? fromDay,
    String? beforeDay,
    int? limit,
    bool remember = false,
  }) async {
    final db = await _db.open();
    if (db == null) {
      final house = await _legacyRead();
      return [
        for (final log in house?.logs ?? const <DoseRecord>[])
          if ((fromDay == null || log.day.compareTo(fromDay) >= 0) &&
              (beforeDay == null || log.day.compareTo(beforeDay) < 0))
            log,
      ].take(limit ?? 1 << 30).toList();
    }
    final where = [
      if (fromDay != null) 'day >= ?',
      if (beforeDay != null) 'day < ?',
    ];
    final rows = await db.query(
      'dose_logs',
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: [?fromDay, ?beforeDay],
      orderBy: 'day DESC, ord DESC',
      limit: limit,
    );
    final logs = _parseRows('dose_logs', rows, LocalRows.toLog, cache: remember);
    if (remember) {
      for (final log in logs) {
        _logObjects[log.id] = log;
      }
    }
    return logs;
  }

  Future<List<T>> _readTable<T>(
    Database db,
    String table,
    T Function(Map<String, Object?>) parse,
  ) async {
    final rows = await db.query(table, orderBy: 'position');
    return _parseRows(table, rows, parse);
  }

  /// One bad row (hand-edited file, a bug in an old build) is skipped and
  /// logged instead of losing the whole household.
  List<T> _parseRows<T>(
    String table,
    List<Map<String, Object?>> rows,
    T Function(Map<String, Object?>) parse, {
    bool cache = true,
  }) {
    final cached = cache ? (_rows[table] ??= {}) : null;
    final out = <T>[];
    var bad = 0;
    for (final row in rows) {
      try {
        out.add(parse(row));
        cached?['${row['id']}'] = row;
      } on Object {
        bad++;
      }
    }
    if (bad > 0) {
      AppLog.event('store.row_corrupt', {'table': table, 'rows': bad});
    }
    return out;
  }

  /// Saves [house]: changed rows are upserted, removed ones deleted, all in
  /// one transaction. On failure nothing is half-saved, `store.write_failed`
  /// is logged and the error rethrown; the next write retries the same rows
  /// (the caller re-sends [StoredHousehold.deletedLogIds]).
  Future<void> write(StoredHousehold house) async {
    final db = await _db.open();
    await _writeToken(house.token);
    if (db == null) {
      await LegacyPrefsStore.writeHousehold(house);
      return;
    }
    _syncGeneration();

    final meta = LegacyPrefsStore.metaRows(house);
    final metaChanges = {
      for (final entry in meta.entries)
        if (_meta[entry.key] != entry.value) entry.key: entry.value,
    };

    final members = _diff('members', [
      for (final (i, m) in house.members.indexed) LocalRows.member(m, i),
    ]);
    final pets = _diff('pets', [
      for (final (i, pet) in house.pets.indexed) LocalRows.pet(pet, i),
    ]);
    final activeIds = {for (final m in house.medications) m.id};
    final medications = _diff('medications', [
      for (final (i, m) in house.medications.indexed)
        LocalRows.medication(m, i),
      for (final (i, m) in house.archivedMedications.indexed)
        if (!activeIds.contains(m.id)) LocalRows.medication(m, i),
    ]);

    // Logs: only days whose list changed (a new or replaced log, or a
    // deletion) are looked at; their logs get ord = place within the day,
    // and only rows whose content or place moved are written. Days load
    // and save whole, so a day's order on disk always matches memory.
    final logCache = house.replaceLogs
        ? <String, Map<String, Object?>>{}
        : (_rows['dose_logs'] ??= {});
    final logDeletes = house.deletedLogIds;
    final touched = <String>{};
    for (final log in house.logs) {
      if (house.replaceLogs || !identical(_logObjects[log.id], log)) {
        touched.add(log.day);
      }
    }
    for (final id in logDeletes) {
      final day = logCache[id]?['day'];
      if (day is String) touched.add(day);
    }
    final byDay = <String, List<DoseRecord>>{};
    if (touched.isNotEmpty) {
      for (final log in house.logs) {
        if (touched.contains(log.day)) (byDay[log.day] ??= []).add(log);
      }
    }
    final logUpserts = <Map<String, Object?>>[];
    for (final logs in byDay.values) {
      for (final (i, log) in logs.indexed) {
        final row = LocalRows.log(log, logs.length - i);
        if (!mapEquals(logCache[log.id], row)) logUpserts.add(row);
      }
    }

    if (metaChanges.isEmpty &&
        members.isEmpty &&
        pets.isEmpty &&
        medications.isEmpty &&
        logUpserts.isEmpty &&
        logDeletes.isEmpty &&
        !house.replaceLogs) {
      lastWriteRows = 0;
      return;
    }

    var table = 'meta';
    try {
      await db.guardedTransaction((txn) async {
        Future<void> run(String name, void Function(Batch batch) fill) async {
          table = name;
          final batch = txn.batch();
          fill(batch);
          await batch.commit(noResult: true);
        }

        await run('meta', (batch) {
          for (final entry in metaChanges.entries) {
            batch.insert('meta', {
              'key': entry.key,
              'value': entry.value,
            }, conflictAlgorithm: ConflictAlgorithm.replace);
          }
        });
        for (final change in [members, pets, medications]) {
          await run(change.table, (batch) => change.apply(batch, _primed));
        }
        await run('dose_logs', (batch) {
          if (house.replaceLogs) batch.delete('dose_logs');
          for (final row in logUpserts) {
            batch.insert(
              'dose_logs',
              row,
              conflictAlgorithm: ConflictAlgorithm.replace,
            );
          }
          for (final id in logDeletes) {
            batch.delete('dose_logs', where: 'id = ?', whereArgs: [id]);
          }
        });
      });
    } on Object catch (error, stack) {
      AppLog.error('store.write_failed', error, stack, {
        'table': table,
        'rows': logUpserts.length + logDeletes.length,
      });
      rethrow;
    }

    // Committed: the cache now describes the disk.
    _rows['dose_logs'] = logCache;
    _meta = {..._meta, ...metaChanges};
    for (final change in [members, pets, medications]) {
      _rows[change.table] = change.after;
    }
    for (final row in logUpserts) {
      logCache['${row['id']}'] = row;
    }
    for (final id in logDeletes) {
      logCache.remove(id);
    }
    if (house.replaceLogs) _logObjects.clear();
    for (final log in house.logs) {
      _logObjects[log.id] = log;
    }
    // Keep the caches to what memory holds, so they never outgrow it.
    if (logCache.length > house.logs.length ||
        _logObjects.length > house.logs.length) {
      final live = {for (final log in house.logs) log.id};
      logCache.removeWhere((id, _) => !live.contains(id));
      _logObjects.removeWhere((id, _) => !live.contains(id));
    }
    _primed = true;
    lastWriteRows =
        metaChanges.length +
        logUpserts.length +
        logDeletes.length +
        [
          members,
          pets,
          medications,
        ].fold(0, (sum, c) => sum + c.upserts.length + c.deletes.length);
  }

  _TableChange _diff(String table, List<Map<String, Object?>> rows) {
    final before = _rows[table] ?? const {};
    final after = {for (final row in rows) '${row['id']}': row};
    return _TableChange(
      table: table,
      after: after,
      upserts: [
        for (final row in rows)
          if (!_primed || !mapEquals(before['${row['id']}'], row)) row,
      ],
      deletes: [
        for (final id in before.keys)
          if (!after.containsKey(id)) id,
      ],
    );
  }

  /// Forgets the household (sign-out, reset). The database file itself is
  /// removed by account deletion (see `LocalDatabase.deleteFile`).
  Future<void> clear() async {
    final db = await _db.open();
    if (db == null) {
      await LegacyPrefsStore.clearHousehold();
    } else {
      _syncGeneration();
      await db.guardedTransaction((txn) async {
        final batch = txn.batch();
        for (final table in const [
          'members',
          'pets',
          'medications',
          'dose_logs',
        ]) {
          batch.delete(table);
        }
        // Keep the migration marker so old blobs are never imported again.
        batch.delete(
          'meta',
          where: 'key <> ?',
          whereArgs: [LegacyPrefsStore.migratedMetaKey],
        );
        await batch.commit(noResult: true);
      });
      _rows.clear();
      _logObjects.clear();
      _meta = {};
      _primed = true;
    }
    await _writeToken(null, force: true);
  }

  // ---------------------------------------------------------------------------
  // Old preferences format, for a run where the database can't be used.

  Future<StoredHousehold?> _legacyRead() async {
    final json = await LegacyPrefsStore.readHouseholdJson();
    if (json == null) {
      if (!await LegacyPrefsStore.sqliteOwnsData()) {
        await _writeToken(null, force: true);
      }
      return null;
    }
    final token = await _legacyToken(json) ?? await _readToken();
    final house = LegacyPrefsStore.parseHousehold(json, token: token);
    if (house == null) await LegacyPrefsStore.clearHousehold();
    return house;
  }

  /// A pre-Keychain build's plain-text token, moved to secure storage once.
  Future<String?> _legacyToken(Map<String, dynamic> json) async {
    final legacy = json['token'];
    if (legacy is! String || legacy.isEmpty) return null;
    try {
      await SecureTokens.write(SecureTokens.householdKey, legacy);
      _savedToken = legacy;
      _tokenKnown = true;
      json.remove('token');
      await LegacyPrefsStore.rewriteHouseholdJson(json);
      AppLog.event('store.token_migrated');
    } on Object catch (error, stack) {
      // Keep the plain copy so the phone stays linked; retried next launch.
      AppLog.error('store.token_migrate_failed', error, stack);
    }
    return legacy;
  }

  // ---------------------------------------------------------------------------
  // Token (secure storage only)

  Future<String?> _readToken() async {
    try {
      final token = await SecureTokens.read(SecureTokens.householdKey);
      _savedToken = token;
      _tokenKnown = true;
      return token;
    } on Object catch (error, stack) {
      AppLog.error('store.token_read_failed', error, stack);
      return null;
    }
  }

  Future<void> _writeToken(String? token, {bool force = false}) async {
    if (!force && _tokenKnown && token == _savedToken) return;
    // Unknown state + no token: leave the Keychain alone (see [_tokenKnown]).
    if (!force && !_tokenKnown && token == null) return;
    try {
      if (token == null || token.isEmpty) {
        await SecureTokens.delete(SecureTokens.householdKey);
      } else {
        await SecureTokens.write(SecureTokens.householdKey, token);
      }
      _savedToken = token;
      _tokenKnown = true;
    } on Object catch (error, stack) {
      AppLog.error('store.token_write_failed', error, stack);
    }
  }
}

/// Pending changes to one small table (members, pets, medications).
class _TableChange {
  const _TableChange({
    required this.table,
    required this.after,
    required this.upserts,
    required this.deletes,
  });

  final String table;
  final Map<String, Map<String, Object?>> after;
  final List<Map<String, Object?>> upserts;
  final List<String> deletes;

  bool get isEmpty => upserts.isEmpty && deletes.isEmpty;

  /// [primed]: the cache describes the disk. Otherwise rows this store never
  /// saw may be on disk, so the table is replaced wholesale.
  void apply(Batch batch, bool primed) {
    if (!primed) batch.delete(table);
    for (final row in upserts) {
      batch.insert(table, row, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    for (final id in deletes) {
      batch.delete(table, where: 'id = ?', whereArgs: [id]);
    }
  }
}
