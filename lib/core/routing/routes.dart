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

  /// [reason] picks the copy and RevenueCat placement; [from] names the
  /// button that led here. Both land on `billing.paywall.opened`, so the
  /// gate doesn’t log a line of its own.
  static String paywallWith({String? reason, String? from}) {
    final query = {
      if (reason != null && reason.isNotEmpty) 'reason': reason,
      if (from != null && from.isNotEmpty) 'from': from,
    };
    return query.isEmpty
        ? paywall
        : Uri(path: paywall, queryParameters: query).toString();
  }

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
