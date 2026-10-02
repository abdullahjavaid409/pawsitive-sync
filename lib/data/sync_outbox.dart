import 'dart:convert';

import 'package:pawsitive_sync/core/logging/app_log.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  Map<String, Object?> toJson() => {
    'id': id,
    'type': type,
    'payload': payload,
  };

  static SyncBatchOp fromJson(Map<String, dynamic> json) => SyncBatchOp(
    id: '${json['id']}',
    type: '${json['type']}',
    payload: Map<String, Object?>.from(json['payload'] as Map? ?? const {}),
  );
}

/// Local-first outbox: changes queue here and flush in one batch API call.
class SyncOutbox {
  SyncOutbox({SharedPreferences? prefs}) : _prefs = prefs;

  static const _key = 'sync_outbox_v1';
  SharedPreferences? _prefs;

  Future<SharedPreferences> _storage() async =>
      _prefs ??= await SharedPreferences.getInstance();

  Future<List<SyncBatchOp>> read() async {
    final raw = (await _storage()).getString(_key);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List;
      return [
        for (final item in list)
          if (item is Map<String, dynamic>) SyncBatchOp.fromJson(item),
      ];
    } catch (_) {
      return [];
    }
  }

  Future<void> write(List<SyncBatchOp> items) async {
    final encoded = jsonEncode([for (final item in items) item.toJson()]);
    await (await _storage()).setString(_key, encoded);
  }

  Future<void> enqueue(SyncBatchOp op) async {
    final items = await read();
    items.add(op);
    await write(items);
    AppLog.event('sync.outbox.enqueued', {'type': op.type, 'id': op.id});
  }

  Future<void> remove(String id) async {
    final items = await read()..removeWhere((op) => op.id == id);
    await write(items);
  }

  Future<void> clear() async {
    await (await _storage()).remove(_key);
  }
}
