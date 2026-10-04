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
    return {
      'version': 1,
      'updatedAt': now.millisecondsSinceEpoch / 1000,
      'hasPets': care.pets.isNotEmpty,
      'days': [
        for (var offset = 0; offset < 8; offset++)
          _day(care, DateTime(now.year, now.month, now.day + offset)),
      ],
    };
  }

  static Map<String, Object?> _day(CareRepository care, DateTime day) {
    final key = dayKey(day);
    final records = {
      for (final record in care.logs.where((log) => log.day == key))
        '${record.medicationId}:${record.part.name}': record,
    };
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

  static Future<void> refresh(CareRepository care) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) return;
    final payload = jsonEncode(snapshot(care));
    if (_lastPayload == payload) return;
    try {
      await _channel.invokeMethod<void>('update', payload);
      _lastPayload = payload;
    } on MissingPluginException {
      // Widget bridge is present only in the native iOS runner.
    } on PlatformException catch (error) {
      AppLog.event('widgets.update_failed', {'code': error.code});
    }
  }
}
