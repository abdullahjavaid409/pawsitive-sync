import 'package:flutter/foundation.dart';
import 'package:pawsitive_sync/core/logging/app_log.dart';
import 'package:pawsitive_sync/domain/models.dart';

/// Stores setup answers until onboarding is marked complete.
class OnboardingViewModel extends ChangeNotifier {
  bool isComplete = false;
  String petName = 'Miso';
  Species species = Species.cat;
  int ageYears = 12;
  String weight = '4.6';
  final Set<String> conditions = {'Diabetes', 'Kidney disease'};
  final Set<String> caregivers = {'Partner or family', 'Pet sitter or walker'};
  bool remindersOn = false;

  static const conditionOptions = [
    ('Diabetes', 'Insulin, usually twice a day'),
    ('Kidney disease', 'Fluids, blood pressure tablets'),
    ('Thyroid', 'Daily tablets or gel'),
    ('Heart condition', 'Several meds at set times'),
    ('Arthritis or pain', 'Daily pain relief, supplements'),
    ('Preventatives only', 'Flea, tick, heartworm'),
  ];

  static const caregiverOptions = [
    'Just me',
    'Partner or family',
    'Pet sitter or walker',
    'Roommates',
  ];

  void setName(String value) {
    final wasEmpty = petName.trim().isEmpty;
    petName = value;
    if (wasEmpty != value.trim().isEmpty) notifyListeners();
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
    weight = value;
  }

  void toggleCondition(String name) {
    if (conditions.contains(name)) {
      conditions.remove(name);
    } else {
      conditions.add(name);
    }
    notifyListeners();
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

  void finish({required bool reminders}) {
    remindersOn = reminders;
    isComplete = true;
    notifyListeners();
    AppLog.event('onboarding.finished', {'reminders': reminders});
  }
}
