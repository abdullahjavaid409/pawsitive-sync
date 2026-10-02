import 'dart:convert';

import 'package:pawsitive_sync/data/household_api.dart';
import 'package:pawsitive_sync/domain/models.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  });

  final String? token;
  final String memberId;
  final String inviteCode;
  final bool isPro;
  final BillingPlan plan;
  final List<Member> members;
  final List<Pet> pets;
  final List<Medication> medications;
  final List<DoseRecord> logs;
}

/// Saves the household as JSON in shared preferences so it survives restarts and works offline.
class HouseholdStore {
  static const _key = 'household_v2';

  Future<StoredHousehold?> read() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return null;
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      List<T> list<T>(String key, T Function(Map<String, dynamic>) map) => [
        for (final item in json[key] as List? ?? const [])
          if (item is Map<String, dynamic>) map(item),
      ];
      return StoredHousehold(
        token: json['token'] as String?,
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
      );
    } on Object {
      await prefs.remove(_key);
      return null;
    }
  }

  Future<void> write(StoredHousehold house) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode({
        'token': house.token,
        'memberId': house.memberId,
        'inviteCode': house.inviteCode,
        'isPro': house.isPro,
        'plan': house.plan.name,
        'members': [for (final member in house.members) member.toJson()],
        'pets': [for (final pet in house.pets) pet.toJson()],
        'medications': [for (final item in house.medications) item.toJson()],
        'logs': [for (final log in house.logs.take(3000)) log.toJson()],
      }),
    );
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
