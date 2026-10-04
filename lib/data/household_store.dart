import 'dart:convert';

import 'package:pawsitive_sync/core/logging/app_log.dart';
import 'package:pawsitive_sync/data/household_api.dart';
import 'package:pawsitive_sync/data/secure_tokens.dart';
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
    this.householdId = '',
    this.archivedMedications = const [],
  });

  final String householdId;
  final String? token;
  final String memberId;
  final String inviteCode;
  final bool isPro;
  final BillingPlan plan;
  final List<Member> members;
  final List<Pet> pets;
  final List<Medication> medications;
  final List<DoseRecord> logs;

  /// Removed medicines kept for vet-report history (local only).
  final List<Medication> archivedMedications;
}

/// Saves the household as JSON in shared preferences so it survives restarts
/// and works offline. The bearer token is kept apart in [SecureTokens]
/// (Keychain / Keystore) and never written to preferences.
class HouseholdStore {
  static const _key = 'household_v2';

  /// Last token known to be in secure storage, so a write touches the
  /// Keychain only when the token actually changed.
  String? _savedToken;

  /// False until secure storage answered once. A failed read must never be
  /// mistaken for "signed out" and wipe a good token on the next write.
  bool _tokenKnown = false;

  Future<StoredHousehold?> read() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) {
      // Nothing saved (fresh install or reinstall). The iOS Keychain outlives
      // an uninstall, so drop any orphaned token from a previous install.
      await _writeToken(null, force: true);
      return null;
    }
    final Map<String, dynamic> json;
    try {
      json = jsonDecode(raw) as Map<String, dynamic>;
    } on Object catch (error, stack) {
      AppLog.error('store.household_corrupt', error, stack);
      await prefs.remove(_key);
      return null;
    }
    final token = await _readToken(prefs, json);
    try {
      List<T> list<T>(String key, T Function(Map<String, dynamic>) map) => [
        for (final item in json[key] as List? ?? const [])
          if (item is Map<String, dynamic>) map(item),
      ];
      return StoredHousehold(
        householdId: json['householdId'] as String? ?? '',
        token: token,
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
        archivedMedications: list('archivedMedications', medicationFromJson),
      );
    } on Object catch (error, stack) {
      AppLog.error('store.household_corrupt', error, stack);
      await prefs.remove(_key);
      return null;
    }
  }

  /// Secure token, migrating a pre-Keychain install's plain-text token once.
  Future<String?> _readToken(
    SharedPreferences prefs,
    Map<String, dynamic> json,
  ) async {
    final legacy = json['token'];
    if (legacy is String && legacy.isNotEmpty) {
      try {
        await SecureTokens.write(SecureTokens.householdKey, legacy);
        _savedToken = legacy;
        _tokenKnown = true;
        json.remove('token');
        await prefs.setString(_key, jsonEncode(json));
        AppLog.event('store.token_migrated');
      } on Object catch (error, stack) {
        // Keep the plain copy so the phone stays linked; retried next launch.
        AppLog.error('store.token_migrate_failed', error, stack);
      }
      return legacy;
    }
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

  Future<void> write(StoredHousehold house) async {
    final prefs = await SharedPreferences.getInstance();
    await _writeToken(house.token);
    await prefs.setString(
      _key,
      jsonEncode({
        'householdId': house.householdId,
        'memberId': house.memberId,
        'inviteCode': house.inviteCode,
        'isPro': house.isPro,
        'plan': house.plan.name,
        'members': [for (final member in house.members) member.toJson()],
        'pets': [for (final pet in house.pets) pet.toStoreJson()],
        'medications': [for (final item in house.medications) item.toJson()],
        'archivedMedications': [
          for (final item in house.archivedMedications) item.toJson(),
        ],
        'logs': [for (final log in house.logs.take(3000)) log.toJson()],
      }),
    );
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
    await _writeToken(null, force: true);
  }
}
