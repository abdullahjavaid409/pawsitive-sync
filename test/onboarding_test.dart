import 'package:flutter_test/flutter_test.dart';
import 'package:pawsitive_sync/core/routing/routes.dart';
import 'package:pawsitive_sync/ui/onboarding/onboarding_view_model.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('fresh onboarding starts empty and invalid until a name is entered', () {
    final model = OnboardingViewModel();

    expect(model.isComplete, isFalse);
    expect(model.hasValidPetName, isFalse);
    expect(model.conditions, isEmpty);
    expect(model.caregivers, isEmpty);
    expect(model.resumeRoute, AppRoutes.welcome);
  });

  test('whitespace-only names are rejected', () {
    final model = OnboardingViewModel()..setName('   ');

    expect(model.hasValidPetName, isFalse);
    expect(model.guardRoute(AppRoutes.petDetails), AppRoutes.pet);
  });

  test('route guards block skipped steps', () {
    final model = OnboardingViewModel()..setName('Miso');

    expect(model.guardRoute(AppRoutes.petDetails), isNull);
    expect(model.guardRoute(AppRoutes.conditions), isNull);
    expect(model.guardRoute(AppRoutes.caregivers), AppRoutes.conditions);
    expect(model.guardRoute(AppRoutes.notifications), AppRoutes.conditions);

    model.toggleCondition('Diabetes');
    expect(model.guardRoute(AppRoutes.caregivers), isNull);
    expect(model.guardRoute(AppRoutes.notifications), AppRoutes.caregivers);

    model.toggleCaregiver('Just me');
    expect(model.guardRoute(AppRoutes.notifications), isNull);
    expect(model.resumeRoute, AppRoutes.notifications);
  });

  test('finish persists completion and is idempotent', () async {
    final model = OnboardingViewModel();

    await model.finish(reminders: false);
    expect(model.isComplete, isTrue);

    await model.finish(reminders: true);
    expect(model.remindersOn, isFalse);

    final loaded = await OnboardingViewModel.load();
    expect(loaded.isComplete, isTrue);
  });

  test('weight accepts blank or simple kg values only', () {
    final model = OnboardingViewModel();

    expect(model.hasValidWeight, isTrue);
    model.setWeight('4.6');
    expect(model.hasValidWeight, isTrue);
    model.setWeight('4.6.1');
    expect(model.hasValidWeight, isFalse);
    model.setWeight('');
    expect(model.hasValidWeight, isTrue);
  });

  test('something else works like any other condition', () {
    final model = OnboardingViewModel()..toggleCondition('Something else');

    expect(model.hasConditions, isTrue);
    expect(model.conditions, {'Something else'});
  });

  test('caregiver selection clears conflicting choices', () {
    final model = OnboardingViewModel()
      ..toggleCaregiver('Partner or family')
      ..toggleCaregiver('Just me');

    expect(model.caregivers, {'Just me'});
    expect(model.caregiverCount, 1);
  });

  test('default caregiver is just me when none picked yet', () {
    final model = OnboardingViewModel();

    model.ensureDefaultCaregiver();

    expect(model.caregivers, {'Just me'});
    expect(model.hasCaregivers, isTrue);
  });
}
