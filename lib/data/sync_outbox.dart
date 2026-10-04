import 'dart:convert';

import 'package:pawsitive_sync/core/logging/app_log.dart';
import 'package:pawsitive_sync/data/legacy_prefs_store.dart';
import 'package:pawsitive_sync/data/local_database.dart';
import 'package:sqflite/sqflite.dart';

/// One queued write waiting for batch sync to the server.
class SyncBatchOp {
  const SyncBatchOp({
    required this.id,
    required this.type,
    required this.payload,
  });

  final String id;
  final String type;
  final Map<String, Object?> payload;

  Map<String, Object?> toJson() => {'id': id, 'type': type, 'payload': payload};

  static SyncBatchOp fromJson(Map<String, dynamic> json) => SyncBatchOp(
    id: '${json['id']}',
    type: '${json['type']}',
    payload: Map<String, Object?>.from(json['payload'] as Map? ?? const {}),
  );
}

/// Local-first outbox: changes queue here and flush in one batch API call.
/// One row per op in [LocalDatabase], in the order they were queued, so
/// queueing a change is one insert and an applied op is one delete.
class SyncOutbox {
  SyncOutbox({this._database});

  final LocalDatabase? _database;
  LocalDatabase get _db => _database ?? LocalDatabase.shared;

  /// Ids of the ops seen in the last read/enqueue, for code that must not
  /// drop a local change the server hasn't received yet.
  Set<String> get pendingIds => {for (final op in _last) op.id};

  /// Record ids still queued, by op type: `{'logDose': {log ids}, …}`.
  Map<String, Set<String>> get pendingPayloadIds {
    final out = <String, Set<String>>{};
    for (final op in _last) {
      final id = op.payload['id'];
      if (id != null) (out[op.type] ??= {}).add('$id');
    }
    return out;
  }

  /// The last known queue (also the only copy when the database is down and
  /// the old store is read-only, see [LegacyPrefsStore.sqliteOwnsData]).
  List<SyncBatchOp> _last = const [];

  Future<List<SyncBatchOp>> read() async {
    final db = await _db.open();
    if (db == null) {
      final saved = await LegacyPrefsStore.readOutbox();
      return [...(saved.isEmpty ? _last : _last = saved)];
    }
    final rows = await db.query('outbox', orderBy: 'seq');
    final ops = <SyncBatchOp>[];
    for (final row in rows) {
      try {
        ops.add(
          SyncBatchOp(
            id: '${row['id']}',
            type: '${row['type']}',
            payload: Map<String, Object?>.from(
              jsonDecode('${row['payload']}') as Map,
            ),
          ),
        );
      } catch (error, stack) {
        // Corrupt op: logged so a lost offline change is never silent.
        AppLog.error('sync.outbox.read_failed', error, stack, {
          'id': '${row['id']}',
        });
      }
    }
    _last = ops;
    return [...ops];
  }

  /// Replaces the whole queue (one transaction).
  Future<void> write(List<SyncBatchOp> items) async {
    final db = await _db.open();
    _last = [...items];
    if (db == null) return LegacyPrefsStore.writeOutbox(items);
    await _guard(
      () => db.transaction((txn) async {
        final batch = txn.batch()..delete('outbox');
        for (final op in items) {
          batch.insert('outbox', _row(op));
        }
        await batch.commit(noResult: true);
      }),
    );
  }

  Future<void> enqueue(SyncBatchOp op) async {
    final db = await _db.open();
    if (db == null) {
      final items = await read()
        ..add(op);
      await write(items);
    } else {
      // Same id again (a retried tap) replaces the queued op, keeping one.
      await _guard(
        () => db.insert(
          'outbox',
          _row(op),
          conflictAlgorithm: ConflictAlgorithm.replace,
        ),
      );
      _last = [..._last.where((item) => item.id != op.id), op];
    }
    AppLog.event('sync.outbox.enqueued', {'type': op.type, 'id': op.id});
  }

  Future<void> remove(String id) => removeAll({id});

  /// Drops every applied op in one transaction.
  Future<void> removeAll(Set<String> ids) async {
    if (ids.isEmpty) return;
    final db = await _db.open();
    if (db == null) {
      final items = await read()
        ..removeWhere((op) => ids.contains(op.id));
      await write(items);
      return;
    }
    await _guard(
      () => db.transaction((txn) async {
        final batch = txn.batch();
        for (final id in ids) {
          batch.delete('outbox', where: 'id = ?', whereArgs: [id]);
        }
        await batch.commit(noResult: true);
      }),
    );
    _last = [..._last.where((op) => !ids.contains(op.id))];
  }

  Future<void> clear() async {
    _last = const [];
    final db = await _db.open();
    if (db == null) return LegacyPrefsStore.clearOutbox();
    await _guard(() => db.delete('outbox'));
  }

  static Map<String, Object?> _row(SyncBatchOp op) => {
    'id': op.id,
    'type': op.type,
    'payload': jsonEncode(op.payload),
  };

  static Future<void> _guard(Future<void> Function() run) async {
    try {
      await run();
    } on Object catch (error, stack) {
      AppLog.error('store.write_failed', error, stack, {'table': 'outbox'});
      rethrow;
    }
  }
}
