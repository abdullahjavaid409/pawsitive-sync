/// Shared limits for pet names, age, and household size.
abstract final class PetLimits {
  static const maxNameLength = 40;
  /// Free tier: one pet. Pro unlocks up to [maxPetsPerHousehold].
  static const maxPetsFree = 1;
  static const maxPetsPerHousehold = 10;
  static const maxAgeYears = 30;
  static const maxConditions = 12;

  static final weightPattern = RegExp(r'^\d{1,2}(\.\d{1,2})?$');

  static bool isValidWeight(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return true;
    return weightPattern.hasMatch(trimmed);
  }

  static double? parseWeightKg(String raw) {
    final trimmed = raw.trim().replaceAll(',', '.');
    if (trimmed.isEmpty) return null;
    return double.tryParse(trimmed);
  }

  static int clampAge(int value) => value.clamp(0, maxAgeYears);
}
