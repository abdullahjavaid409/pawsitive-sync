import 'package:flutter/foundation.dart' show mapEquals;
import 'package:pawsitive_sync/core/logging/app_log.dart';
import 'package:pawsitive_sync/data/legacy_prefs_store.dart';
import 'package:pawsitive_sync/data/local_database.dart';
import 'package:pawsitive_sync/domain/models.dart';
import 'package:sqflite/sqflite.dart';

/// Local vet visits and vaccine due dates (device-first; sync later), one
/// row per event in [LocalDatabase].
class CareEventsStore {
  CareEventsStore({this._database});

  final LocalDatabase? _database;
  LocalDatabase get _db => _database ?? LocalDatabase.shared;

  /// Rows as last read/written (null: unknown, so the next write replaces
  /// the table).
  Map<String, Map<String, Object?>>? _rows;
  int _generation = -1;

  Future<List<CareEvent>> read() async {
    final db = await _db.open();
    if (db == null) return LegacyPrefsStore.readEvents();
    final rows = await db.query('care_events', orderBy: 'position');
    final events = <CareEvent>[];
    final cache = <String, Map<String, Object?>>{};
    var bad = 0;
    for (final row in rows) {
      try {
        events.add(LocalRows.toCareEvent(row));
        cache['${row['id']}'] = row;
      } on Object {
        bad++;
      }
    }
    if (bad > 0) {
      AppLog.event('store.row_corrupt', {'table': 'care_events', 'rows': bad});
    }
    _rows = cache;
    _generation = _db.generation;
    return events;
  }

  /// Saves [events] as the full list: changed rows upserted, missing ones
  /// deleted, in one transaction. Logs `store.write_failed` and rethrows.
  Future<void> write(List<CareEvent> events) async {
    final db = await _db.open();
    if (db == null) return LegacyPrefsStore.writeEvents(events);
    final before = _generation == _db.generation ? _rows : null;
    final after = {
      for (final (i, event) in events.indexed)
        event.id: LocalRows.careEvent(event, i),
    };
    try {
      await db.guardedTransaction((txn) async {
        final batch = txn.batch();
        if (before == null) batch.delete('care_events');
        for (final row in after.values) {
          if (before != null && mapEquals(before[row['id']], row)) continue;
          batch.insert(
            'care_events',
            row,
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
        for (final id in before?.keys ?? const <String>[]) {
          if (!after.containsKey(id)) {
            batch.delete('care_events', where: 'id = ?', whereArgs: [id]);
          }
        }
        await batch.commit(noResult: true);
      });
    } on Object catch (error, stack) {
      AppLog.error('store.write_failed', error, stack, {
        'table': 'care_events',
      });
      rethrow;
    }
    _rows = after;
    _generation = _db.generation;
  }

  Future<void> clear() async {
    final db = await _db.open();
    if (db == null) return LegacyPrefsStore.clearEvents();
    await db.delete('care_events');
    _rows = {};
    _generation = _db.generation;
  }
}
