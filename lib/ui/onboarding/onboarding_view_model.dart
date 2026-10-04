import 'package:flutter/foundation.dart';
import 'package:pawsitive_sync/core/logging/app_log.dart';
import 'package:pawsitive_sync/core/routing/routes.dart';
import 'package:pawsitive_sync/core/constants/pet_limits.dart';
import 'package:pawsitive_sync/data/analytics_service.dart';
import 'package:pawsitive_sync/data/onboarding_profile.dart';
import 'package:pawsitive_sync/data/onboarding_state.dart';
import 'package:pawsitive_sync/data/reminder_choice.dart';
import 'package:pawsitive_sync/domain/models.dart';
import 'package:pawsitive_sync/domain/pet_conditions.dart';

/// Stores setup answers until onboarding is marked complete.
class OnboardingViewModel extends ChangeNotifier {
  bool isComplete = false;
  String petName = '';
  Species species = Species.cat;
  int ageYears = 0;
  String weight = '';
  final Set<String> conditions = {};
  final Set<String> caregivers = {};
  bool remindersOn = false;
  Uint8List? photoBytes;
  static const maxPetNameLength = PetLimits.maxNameLength;

  static const conditionOptions = PetConditions.options;

  static const caregiverOptions = [
    'Just me',
    'Partner or family',
    'Pet sitter or walker',
    'Roommates',
  ];

  static Future<OnboardingViewModel> load() async {
    final model = OnboardingViewModel();
    final results = await Future.wait<bool>([
      OnboardingState.read(),
      ReminderChoice.read(),
    ]);
    model.isComplete = results[0];
    model.remindersOn = results[1];
    if (model.isComplete) {
      await OnboardingProfile.applyTo(model);
    }
    return model;
  }

  bool get hasValidPetName {
    final trimmed = petName.trim();
    return trimmed.isNotEmpty && trimmed.length <= maxPetNameLength;
  }

  bool get hasConditions => conditions.isNotEmpty;

  bool get hasCaregivers => caregivers.isNotEmpty;

  String get resumeRoute {
    if (isComplete) return AppRoutes.today;
    if (!hasValidPetName) return AppRoutes.welcome;
    if (!hasConditions) return AppRoutes.petDetails;
    if (caregivers.isEmpty) return AppRoutes.caregivers;
    return AppRoutes.notifications;
  }

  static String backRouteForStep(int step) => switch (step) {
    1 => AppRoutes.welcome,
    2 => AppRoutes.pet,
    3 => AppRoutes.petDetails,
    4 => AppRoutes.conditions,
    5 => AppRoutes.caregivers,
    _ => AppRoutes.welcome,
  };

  /// Sends deep links and manual URL edits back to the earliest missing step.
  String? guardRoute(String location) {
    if (isComplete) return null;
    return switch (location) {
      AppRoutes.petDetails when !hasValidPetName => AppRoutes.pet,
      AppRoutes.conditions when !hasValidPetName => AppRoutes.pet,
      AppRoutes.caregivers when !hasValidPetName => AppRoutes.pet,
      AppRoutes.caregivers when !hasConditions => AppRoutes.conditions,
      AppRoutes.notifications when !hasValidPetName => AppRoutes.pet,
      AppRoutes.notifications when !hasConditions => AppRoutes.conditions,
      AppRoutes.notifications when caregivers.isEmpty => AppRoutes.caregivers,
      _ => null,
    };
  }

  void setName(String value) {
    if (value.length > maxPetNameLength) return;
    final wasValid = hasValidPetName;
    petName = value;
    if (wasValid != hasValidPetName) notifyListeners();
  }

  void setPhoto(Uint8List? bytes) {
    photoBytes = bytes;
    notifyListeners();
  }

  void setSpecies(Species value) {
    species = value;
    notifyListeners();
  }

  void changeAge(int delta) {
    ageYears = (ageYears + delta).clamp(0, 30);
    notifyListeners();
  }

  void setWeight(String value) {
    final wasValid = hasValidWeight;
    weight = value;
    if (wasValid != hasValidWeight) notifyListeners();
  }

  bool get hasValidWeight => PetLimits.isValidWeight(weight);

  void toggleCondition(String name) {
    if (conditions.contains(name)) {
      conditions.remove(name);
    } else {
      conditions.add(name);
    }
    notifyListeners();
  }

  void ensureDefaultCaregiver() {
    if (caregivers.isEmpty) {
      caregivers.add('Just me');
      notifyListeners();
    }
  }

  void toggleCaregiver(String name) {
    if (name == 'Just me') {
      caregivers
        ..clear()
        ..add(name);
    } else {
      caregivers.remove('Just me');
      if (caregivers.contains(name)) {
        caregivers.remove(name);
      } else {
        caregivers.add(name);
      }
    }
    notifyListeners();
  }

  int get caregiverCount {
    if (caregivers.contains('Just me') || caregivers.isEmpty) return 1;
    return 1 + caregivers.length;
  }

  void chooseReminders(bool on) {
    remindersOn = on;
    notifyListeners();
    AppLog.event(on ? 'reminders.on' : 'reminders.off');
  }

  /// Changes reminders after setup and remembers the choice.
  Future<void> saveReminders(bool on) async {
    chooseReminders(on);
    await ReminderChoice.write(on);
  }

  Future<void> finish({required bool reminders}) async {
    if (isComplete) return;
    remindersOn = reminders;
    isComplete = true;
    notifyListeners();
    await Future.wait([
      ReminderChoice.write(reminders),
      OnboardingState.write(true),
      OnboardingProfile.write(this),
    ]);
    // Counted for the funnel, but no log line of its own:
    // household.created_from_onboarding (with reminders) or household.joined
    // already says how setup ended.
    AnalyticsService.track('onboarding.finished');
  }

  /// Clears setup state after account deletion so welcome shows again.
  void resetForSignOut() {
    isComplete = false;
    petName = '';
    species = Species.cat;
    ageYears = 0;
    weight = '';
    conditions.clear();
    caregivers.clear();
    remindersOn = false;
    photoBytes = null;
    notifyListeners();
  }
}
