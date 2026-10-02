import 'dart:convert';

import 'package:pawsitive_sync/domain/models.dart';
import 'package:pawsitive_sync/ui/onboarding/onboarding_view_model.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Keeps onboarding answers on device so the home screen stays personal.
class OnboardingProfile {
  static const _key = 'onboarding_profile';

  static Future<void> write(OnboardingViewModel model) async {
    if (!model.hasValidPetName) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _key,
        jsonEncode({
          'petName': model.petName.trim(),
          'species': model.species.name,
          'ageYears': model.ageYears,
          'weight': model.weight.trim(),
          'conditions': model.conditions.toList(),
          'caregivers': model.caregivers.toList(),
        }),
      );
    } catch (_) {}
  }

  static Future<void> applyTo(OnboardingViewModel model) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null) return;
      final map = jsonDecode(raw) as Map<String, dynamic>;
      model.petName = map['petName'] as String? ?? '';
      model.species = _species(map['species'] as String?);
      model.ageYears = map['ageYears'] as int? ?? 0;
      model.weight = map['weight'] as String? ?? '';
      model.conditions
        ..clear()
        ..addAll((map['conditions'] as List?)?.cast<String>() ?? const []);
      model.caregivers
        ..clear()
        ..addAll((map['caregivers'] as List?)?.cast<String>() ?? const []);
    } catch (_) {}
  }

  /// Keeps the saved setup profile aligned when the first pet is edited.
  static Future<void> syncFromPet(Pet pet) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null) return;
      final map = jsonDecode(raw) as Map<String, dynamic>;
      await prefs.setString(
        _key,
        jsonEncode({
          ...map,
          'petName': pet.name,
          'species': pet.species.name,
          'ageYears': pet.ageYears,
          'weight': pet.weightKg > 0 ? '${pet.weightKg}' : '',
          'conditions': pet.conditions,
        }),
      );
    } catch (_) {}
  }

  static Future<void> clear() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_key);
    } catch (_) {}
  }

  static Species _species(String? name) {
    return Species.values.firstWhere(
      (value) => value.name == name,
      orElse: () => Species.cat,
    );
  }
}
