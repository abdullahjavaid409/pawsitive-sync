import 'package:pawsitive_sync/core/logging/app_log.dart';
import 'package:pawsitive_sync/data/household_api.dart';
import 'package:pawsitive_sync/data/sync_outbox.dart';
import 'package:pawsitive_sync/domain/models.dart';

/// Applies outbox entries via POST /v1/sync/batch.
class SyncEngine {
  SyncEngine({SyncOutbox? outbox}) : _outbox = outbox ?? SyncOutbox();

  final SyncOutbox _outbox;

  SyncOutbox get outbox => _outbox;

  Future<BatchFlushResult> flush(HouseholdApi api) async {
    final pending = await _outbox.read();
    if (pending.isEmpty) {
      return const BatchFlushResult(applied: 0);
    }
    AppLog.event('sync.batch.start', {'count': pending.length});
    final response = await api.syncBatch([for (final op in pending) op]);
    final applied = <String>[];
    final sentLogIds = {
      for (final op in pending)
        if (op.type == 'logDose') op.id: op.payload['id'],
    };
    String? conflictMessage;
    DoseRecord? conflictLog;
    for (final result in response.results) {
      if (result.status == 'ok' ||
          result.status == 'missing' ||
          result.status == 'error') {
        applied.add(result.id);
        if (result.status == 'error') {
          AppLog.event('sync.batch.op_rejected', {
            'id': result.id,
            'message': result.message ?? '',
          });
        }
      } else if (result.status == 'conflict') {
        applied.add(result.id);
        final log = result.log;
        // Our own dose already saved (reply lost on a bad network) is not a
        // double dose — only someone else's log is.
        if (log != null && log.id != sentLogIds[result.id]) {
          conflictMessage =
              'Someone already logged this dose at ${log.timeLabel}.';
          conflictLog ??= log;
        }
      }
    }
    for (final id in applied) {
      await _outbox.remove(id);
    }
    AppLog.event('sync.batch.completed', {
      'applied': applied.length,
      'remaining': pending.length - applied.length,
    });
    return BatchFlushResult(
      applied: applied.length,
      household: response.household,
      conflictMessage: conflictMessage,
      conflictLog: conflictLog,
    );
  }
}

class BatchFlushResult {
  const BatchFlushResult({
    required this.applied,
    this.household,
    this.conflictMessage,
    this.conflictLog,
  });

  final int applied;
  final HouseholdSnapshot? household;
  final String? conflictMessage;
  final DoseRecord? conflictLog;
}
