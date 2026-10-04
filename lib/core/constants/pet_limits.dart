/// Shared limits for pet names, age, and household size.
abstract final class PetLimits {
  static const maxNameLength = 40;

  /// Free tier: one pet. Pro unlocks up to [maxPetsPerHousehold].
  static const maxPetsFree = 1;
  static const maxPetsPerHousehold = 10;

  /// Free tier: active medicines per pet. Pro has no cap. Logging the
  /// doses of medicines already on the schedule is never limited.
  static const maxMedsPerPetFree = 1;

  /// Free tier: a new medicine gets one dose time a day, the morning one
  /// (so one reminder). Existing schedules keep every time they already
  /// have; logging any dose is never limited.
  static const maxDoseTimesPerDayFree = 1;

  /// Free tier: the morning reminder stays in the morning (4:00–11:59 AM),
  /// so it can't be moved to stand in for an evening dose. A time saved
  /// earlier (while on Pro) is kept; only new picks are checked.
  static const freeMorningFirstMinute = 4 * 60;
  static const freeMorningLastMinute = 12 * 60 - 1;

  /// Free tier: days of dose history shown. Older logs stay stored (and
  /// still back the double-dose check); Pro shows them again.
  static const freeHistoryDays = 30;
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
