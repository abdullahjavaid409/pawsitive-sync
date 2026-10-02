/// Location constants used by the router and the screens.
abstract final class AppRoutes {
  static const welcome = '/';
  static const onboarding = '/onboarding';
  static const pet = '/onboarding/pet';
  static const petDetails = '/onboarding/details';
  static const conditions = '/onboarding/conditions';
  static const caregivers = '/onboarding/caregivers';
  static const notifications = '/onboarding/notifications';
  static const paywall = '/paywall';

  static String paywallWith({String? reason}) =>
      reason == null || reason.isEmpty ? paywall : '$paywall?reason=$reason';
  static const today = '/today';
  static const pets = '/pets';
  static const household = '/household';
  static const reports = '/reports';
  static const schedule = '/schedule';
  static const invite = '/invite';
  static const lock = '/lock';
  static const join = '/join';
  static const addPet = '/add-pet';
  static const editPetPath = '/edit-pet/:id';
  static const settings = '/settings';
  static const medicationPath = '/medication/:id';

  static String medication(String id) => '/medication/$id';
  static String editPet(String id) => '/edit-pet/$id';
}
