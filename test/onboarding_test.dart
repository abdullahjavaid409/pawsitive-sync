import 'package:flutter_test/flutter_test.dart';
import 'package:pawsitive_sync/core/routing/routes.dart';
import 'package:pawsitive_sync/ui/meds/medicine_forms.dart';
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
    expect(model.guardRoute(AppRoutes.firstMedicine), AppRoutes.pet);
  });

  test('route guards block skipped steps (v14: pet, medicine, household, '
      'notifications, ready)', () {
    final model = OnboardingViewModel();
    expect(model.guardRoute(AppRoutes.caregivers), AppRoutes.pet);

    model.setName('Miso');
    expect(model.resumeRoute, AppRoutes.firstMedicine);
    expect(model.guardRoute(AppRoutes.firstMedicine), isNull);
    expect(model.guardRoute(AppRoutes.caregivers), isNull);
    expect(model.guardRoute(AppRoutes.ready), AppRoutes.caregivers);

    model.householdDone = true;
    expect(model.resumeRoute, AppRoutes.notifications);
    expect(model.guardRoute(AppRoutes.ready), AppRoutes.notifications);

    model.chooseReminders(false);
    expect(model.resumeRoute, AppRoutes.ready);
    expect(model.guardRoute(AppRoutes.ready), isNull);
  });

  test('medicine draft: form picks the unit, amount reads naturally', () {
    final model = OnboardingViewModel()..setForm(MedicineForm.injection);
    expect(model.medUnit, 'units');
    model.medAmount = '2';
    expect(model.medAmountText, '2 units');
    model.setForm(MedicineForm.tablet);
    expect(model.medUnit, 'tablet');
    model.medAmount = '0.5';
    expect(model.medAmountText, '½ tablet');
    model.medAmount = 'abc';
    expect(model.medAmountText, '');
  });

  test('invites are trimmed, lower-cased and never duplicated', () {
    final model = OnboardingViewModel()
      ..addInvite(' Sara@Example.com ')
      ..addInvite('sara@example.com')
      ..addInvite('');
    expect(model.invites, ['sara@example.com']);
    model.removeInvite('sara@example.com');
    expect(model.invites, isEmpty);
  });

  test('sign-out reset clears the medicine and invite drafts', () {
    final model = OnboardingViewModel()
      ..setName('Miso')
      ..setForm(MedicineForm.drops)
      ..addInvite('a@b.co');
    model
      ..medName = 'Ofloxacin'
      ..hasMedicine = true
      ..householdDone = true
      ..inviteAfterSetup = true;
    model.resetForSignOut();
    expect(model.medName, '');
    expect(model.medForm, MedicineForm.tablet);
    expect(model.hasMedicine, isFalse);
    expect(model.invites, isEmpty);
    expect(model.householdDone, isFalse);
    expect(model.inviteAfterSetup, isFalse);
    expect(model.remindersAnswered, isFalse);
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
