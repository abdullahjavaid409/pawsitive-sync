import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:pawsitive_sync/core/logging/app_log.dart';
import 'package:pawsitive_sync/data/care_repository.dart';
import 'package:pawsitive_sync/domain/models.dart';

/// Publishes a small, local care snapshot to the WidgetKit app group.
/// Widget taps open the app; they never record a dose in the background.
class AppleWidgets {
  static const _channel = MethodChannel('pawsitive_sync/widgets');
  static String? _lastPayload;

  static Map<String, Object?> snapshot(CareRepository care) {
    final now = care.now;
    final days = [
      for (var offset = 0; offset < 8; offset++)
        DateTime(now.year, now.month, now.day + offset),
    ];
    // One pass over history for all 8 days (was one full scan per day).
    final byDay = <String, Map<String, DoseRecord>>{
      for (final day in days) dayKey(day): {},
    };
    for (final record in care.logs) {
      // Same overwrite order as before (later entries in the list win).
      byDay[record.day]?['${record.medicationId}:${record.part.name}'] =
          record;
    }
    return {
      'version': 1,
      'updatedAt': now.millisecondsSinceEpoch / 1000,
      'hasPets': care.pets.isNotEmpty,
      'days': [
        for (final day in days) _day(care, day, byDay[dayKey(day)]!),
      ],
    };
  }

  static Map<String, Object?> _day(
    CareRepository care,
    DateTime day,
    Map<String, DoseRecord> records,
  ) {
    final key = dayKey(day);
    return {
      'startsAt': day.millisecondsSinceEpoch / 1000,
      'doses': [
        for (final medicine in care.medications.where(
          (med) => med.isActiveOn(key),
        ))
          for (final part in medicine.parts)
            if (records['${medicine.id}:${part.name}']?.outcome !=
                LogOutcome.skipped)
              {
                'id': CareRepository.doseIdFor(medicine.id, part),
                'pet': care.petById(medicine.petId).name,
                'medicine': medicine.name,
                'amount': medicine.amount,
                'dueAt':
                    DateTime(
                      day.year,
                      day.month,
                      day.day,
                      part.opensAt,
                    ).millisecondsSinceEpoch /
                    1000,
                'scheduledAt':
                    DateTime(
                      day.year,
                      day.month,
                      day.day,
                      part.hour,
                    ).millisecondsSinceEpoch /
                    1000,
                'state':
                    records['${medicine.id}:${part.name}']?.outcome.name ??
                    'pending',
              },
      ],
    };
  }

  static bool _bridgeMissingLogged = false;

  /// Pushes the snapshot only when it changed since the last push.
  static Future<void> refresh(CareRepository care) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) return;
    final data = snapshot(care);
    // updatedAt changes on every call; compare the content only, or every
    // repository notify would re-push (and re-log) an identical widget.
    final content = jsonEncode({...data}..remove('updatedAt'));
    if (_lastPayload == content) return;
    final payload = jsonEncode(data);
    try {
      await _channel.invokeMethod<void>('update', payload);
      _lastPayload = content;
      final days = data['days']! as List;
      AppLog.event('widgets.refreshed', {
        'doses': days.isEmpty ? 0 : ((days.first as Map)['doses'] as List).length,
        'bytes': payload.length,
      });
    } on MissingPluginException {
      // Widget bridge is present only in the native iOS runner.
      if (!_bridgeMissingLogged) {
        _bridgeMissingLogged = true;
        AppLog.event('widgets.unavailable', {'reason': 'no_bridge'});
      }
    } on PlatformException catch (error, stack) {
      AppLog.error('widgets.update_failed', error, stack, {'code': error.code});
    } catch (error, stack) {
      AppLog.error('widgets.update_failed', error, stack);
    }
  }
}
