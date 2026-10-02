import 'dart:convert';

import 'package:pawsitive_sync/domain/models.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Local vet visits and vaccine due dates (device-first; sync later).
class CareEventsStore {
  static const _key = 'care_events_v1';

  Future<List<CareEvent>> read() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return const [];
    try {
      final list = jsonDecode(raw) as List;
      return [
        for (final item in list)
          if (item is Map<String, dynamic>) CareEvent.fromJson(item),
      ];
    } on Object {
      await prefs.remove(_key);
      return const [];
    }
  }

  Future<void> write(List<CareEvent> events) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode([for (final event in events) event.toJson()]),
    );
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
