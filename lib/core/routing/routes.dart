/// Location constants used by the router and the screens.
abstract final class AppRoutes {
  static const welcome = '/';
  static const onboarding = '/onboarding';
  static const day = '/onboarding/day';
  static const pet = '/onboarding/pet';
  static const petDetails = '/onboarding/details';
  static const conditions = '/onboarding/conditions';
  static const caregivers = '/onboarding/caregivers';
  static const notifications = '/onboarding/notifications';
  static const paywall = '/paywall';
  static const today = '/today';
  static const pets = '/pets';
  static const household = '/household';
  static const reports = '/reports';
  static const schedule = '/schedule';
  static const invite = '/invite';
  static const lock = '/lock';
  static const medicationPath = '/medication/:id';

  static String medication(String id) => '/medication/$id';
}
