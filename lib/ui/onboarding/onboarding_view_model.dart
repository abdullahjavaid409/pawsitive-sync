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
import 'package:pawsitive_sync/ui/meds/medicine_forms.dart';

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

  /// v14 setup step 2: the first medicine, kept here until the pet exists
  /// (saved by the paywall's finish, after `applyOnboarding`). Skippable.
  String medName = '';
  MedicineForm medForm = MedicineForm.tablet;
  String medAmount = '';
  String medUnit = MedicineForm.tablet.units.first;

  /// 1 every day, 2 every other day, 7 weekly.
  int medEveryDays = 1;

  /// The form starts unpicked (it sets units and suggestions); frequency
  /// defaults to every day, the most common schedule.
  bool medFormPicked = false;
  bool medEveryPicked = true;
  final Set<DayPart> medParts = {DayPart.morning};
  bool medWithFood = false;

  /// Drops and topicals: where it's given ("Left eye").
  String medSite = '';

  /// Doses on hand; blank means supply isn't tracked.
  String medSupply = '';

  /// True once the medicine step was completed (not skipped).
  bool hasMedicine = false;

  /// v14 setup step 3: people to invite, by email. Sent from the invite
  /// flow once setup is done (inviting needs the household online).
  final List<String> invites = [];

  /// Set once the person moves past the household step (with or without
  /// invites), so resuming setup lands on the right step.
  bool householdDone = false;

  /// "Share an invite link instead" or emails added: the invite flow opens
  /// right after setup (or Pro first, since inviting is a Pro feature).
  bool inviteAfterSetup = false;

  /// Set once notifications were answered; the next step is "all set".
  bool remindersAnswered = false;
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

  /// v14 setup: pet → first medicine → household → notifications → ready.
  String get resumeRoute {
    if (isComplete) return AppRoutes.today;
    if (!hasValidPetName) return AppRoutes.welcome;
    if (!householdDone) return AppRoutes.firstMedicine;
    if (!remindersAnswered) return AppRoutes.notifications;
    return AppRoutes.ready;
  }

  static String backRouteForStep(int step) => switch (step) {
    1 => AppRoutes.welcome,
    2 => AppRoutes.pet,
    3 => AppRoutes.firstMedicine,
    4 => AppRoutes.caregivers,
    _ => AppRoutes.welcome,
  };

  /// Sends deep links and manual URL edits back to the earliest missing step.
  String? guardRoute(String location) {
    if (isComplete) return null;
    final later = {
      AppRoutes.firstMedicine,
      AppRoutes.caregivers,
      AppRoutes.notifications,
      AppRoutes.ready,
    };
    if (later.contains(location) && !hasValidPetName) return AppRoutes.pet;
    if (location == AppRoutes.ready && !remindersAnswered) {
      return householdDone ? AppRoutes.notifications : AppRoutes.caregivers;
    }
    return null;
  }

  /// The medicine step's draft changed (any field).
  void updateMedicine(void Function(OnboardingViewModel m) change) {
    change(this);
    notifyListeners();
  }

  void setForm(MedicineForm form) {
    if (form == medForm && medFormPicked) return;
    medFormPicked = true;
    medForm = form;
    medUnit = form.units.isEmpty ? '' : form.units.first;
    notifyListeners();
  }

  /// "2 units", "½ tablet"; empty when no amount was typed.
  String get medAmountText {
    final qty = double.tryParse(medAmount.trim());
    if (qty == null || qty <= 0) return '';
    return formatDose(qty, medUnit);
  }

  /// An address from setup was invited from Household: stop listing it.
  void inviteSent(String email) {
    final value = email.trim().toLowerCase();
    if (invites.remove(value)) notifyListeners();
  }

  void addInvite(String email) {
    final value = email.trim().toLowerCase();
    if (value.isEmpty || invites.contains(value)) return;
    invites.add(value);
    notifyListeners();
  }

  void removeInvite(String email) {
    invites.remove(email);
    notifyListeners();
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
    speciesPicked = true;
    notifyListeners();
  }

  /// Unpicked until tapped: a wrong guess ("Cat" for a dog) would also
  /// suggest the wrong medicines on the next step.
  bool speciesPicked = false;

  /// The pet step can continue: a name and a species.
  bool get petStepDone => hasValidPetName && speciesPicked;

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
    remindersAnswered = true;
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
    speciesPicked = false;
    ageYears = 0;
    weight = '';
    conditions.clear();
    caregivers.clear();
    remindersOn = false;
    photoBytes = null;
    medName = '';
    medForm = MedicineForm.tablet;
    medAmount = '';
    medUnit = MedicineForm.tablet.units.first;
    medEveryDays = 1;
    medFormPicked = false;
    medEveryPicked = true;
    medParts
      ..clear()
      ..add(DayPart.morning);
    medWithFood = false;
    medSite = '';
    medSupply = '';
    hasMedicine = false;
    invites.clear();
    householdDone = false;
    inviteAfterSetup = false;
    remindersAnswered = false;
    notifyListeners();
  }
}
