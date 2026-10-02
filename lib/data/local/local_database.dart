import 'dart:convert';

import 'package:pawsitive_sync/core/logging/app_log.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

/// Phase 3 SQLite layer — outbox + optional migration from SharedPreferences.
class LocalDatabase {
  LocalDatabase._(this._db);

  static LocalDatabase? _instance;
  final Database _db;

  static Future<LocalDatabase> open() async {
    if (_instance != null) return _instance!;
    final dir = await getApplicationDocumentsDirectory();
    final path = p.join(dir.path, 'pawsitive_local_v1.db');
    final db = await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE outbox (
            id TEXT PRIMARY KEY,
            type TEXT NOT NULL,
            payload TEXT NOT NULL,
            created_at INTEGER NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT NOT NULL)
        ''');
      },
    );
    _instance = LocalDatabase._(db);
    await _instance!._migrateFromSharedPreferences();
    AppLog.event('local_db.opened');
    return _instance!;
  }

  Future<void> _migrateFromSharedPreferences() async {
    final migrated = Sqflite.firstIntValue(
      await _db.rawQuery("SELECT value FROM meta WHERE key = 'sp_migrated'"),
    );
    if (migrated == 1) return;
    final prefs = await SharedPreferences.getInstance();
    final outboxRaw = prefs.getString('sync_outbox_v1');
    if (outboxRaw != null && outboxRaw.isNotEmpty) {
      try {
        final list = jsonDecode(outboxRaw) as List;
        final batch = _db.batch();
        for (final item in list) {
          if (item is! Map<String, dynamic>) continue;
          batch.insert('outbox', {
            'id': item['id'],
            'type': item['type'],
            'payload': jsonEncode(item['payload']),
            'created_at': DateTime.now().millisecondsSinceEpoch,
          }, conflictAlgorithm: ConflictAlgorithm.ignore);
        }
        await batch.commit(noResult: true);
      } catch (_) {}
    }
    await _db.insert(
      'meta',
      {'key': 'sp_migrated', 'value': '1'},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    AppLog.event('local_db.migrated');
  }

  Future<void> close() async {
    await _db.close();
    _instance = null;
  }
}
