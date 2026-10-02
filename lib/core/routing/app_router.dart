import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:pawsitive_sync/core/layout/adaptive.dart';
import 'package:pawsitive_sync/core/logging/app_log.dart';
import 'package:pawsitive_sync/core/routing/app_route_observer.dart';
import 'package:pawsitive_sync/core/routing/app_shell.dart';
import 'package:pawsitive_sync/core/routing/routes.dart';
import 'package:pawsitive_sync/ui/household/household_screen.dart';
import 'package:pawsitive_sync/ui/household/invite_screen.dart';
import 'package:pawsitive_sync/ui/meds/medication_screen.dart';
import 'package:pawsitive_sync/ui/meds/schedule_screen.dart';
import 'package:pawsitive_sync/ui/onboarding/caregivers_screen.dart';
import 'package:pawsitive_sync/ui/onboarding/day_preview_screen.dart';
import 'package:pawsitive_sync/ui/onboarding/conditions_screen.dart';
import 'package:pawsitive_sync/ui/onboarding/notifications_screen.dart';
import 'package:pawsitive_sync/ui/onboarding/onboarding_view_model.dart';
import 'package:pawsitive_sync/ui/onboarding/pet_basics_screen.dart';
import 'package:pawsitive_sync/ui/onboarding/pet_details_screen.dart';
import 'package:pawsitive_sync/ui/onboarding/welcome_screen.dart';
import 'package:pawsitive_sync/ui/paywall/paywall_screen.dart';
import 'package:pawsitive_sync/ui/pets/pet_profile_screen.dart';
import 'package:pawsitive_sync/ui/reports/vet_report_screen.dart';
import 'package:pawsitive_sync/ui/today/lock_screen.dart';
import 'package:pawsitive_sync/ui/today/today_screen.dart';

/// Creates the router, the onboarding redirect, and the tab shell.
GoRouter createRouter(OnboardingViewModel onboarding) {
  final rootNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'root');
  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: AppRoutes.welcome,
    refreshListenable: onboarding,
    observers: [AppRouteObserver()],
    redirect: (context, state) {
      final location = state.matchedLocation;
      final open =
          location == AppRoutes.welcome ||
          location.startsWith(AppRoutes.onboarding) ||
          location == AppRoutes.paywall ||
          location == AppRoutes.lock;
      if (!onboarding.isComplete && !open) {
        AppLog.event('nav.redirect', {
          'from': location,
          'to': AppRoutes.welcome,
        });
        return AppRoutes.welcome;
      }
      if (onboarding.isComplete &&
          (location == AppRoutes.welcome ||
              location.startsWith(AppRoutes.onboarding))) {
        AppLog.event('nav.redirect', {'from': location, 'to': AppRoutes.today});
        return AppRoutes.today;
      }
      return null;
    },
    errorBuilder: (context, state) =>
        AdaptivePage(child: NotFoundScreen(path: state.uri.toString())),
    routes: [
      GoRoute(
        path: AppRoutes.welcome,
        builder: (context, state) => const AdaptivePage(child: WelcomeScreen()),
      ),
      GoRoute(
        path: AppRoutes.day,
        builder: (context, state) =>
            const AdaptivePage(child: DayPreviewScreen()),
      ),
      GoRoute(
        path: AppRoutes.pet,
        builder: (context, state) =>
            const AdaptivePage(child: PetBasicsScreen()),
      ),
      GoRoute(
        path: AppRoutes.petDetails,
        builder: (context, state) =>
            const AdaptivePage(child: PetDetailsScreen()),
      ),
      GoRoute(
        path: AppRoutes.conditions,
        builder: (context, state) =>
            const AdaptivePage(child: ConditionsScreen()),
      ),
      GoRoute(
        path: AppRoutes.caregivers,
        builder: (context, state) =>
            const AdaptivePage(child: CaregiversScreen()),
      ),
      GoRoute(
        path: AppRoutes.notifications,
        builder: (context, state) =>
            const AdaptivePage(child: NotificationsScreen()),
      ),
      GoRoute(
        path: AppRoutes.paywall,
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => const AdaptivePage(child: PaywallScreen()),
      ),
      GoRoute(
        path: AppRoutes.lock,
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => const AdaptivePage(child: LockScreen()),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            AppShell(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.today,
                builder: (context, state) => const TodayScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.pets,
                builder: (context, state) => const PetProfileScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.household,
                builder: (context, state) => const HouseholdScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.reports,
                builder: (context, state) => const VetReportScreen(),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: AppRoutes.medicationPath,
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => AdaptivePage(
          child: MedicationScreen(medicationId: state.pathParameters['id']!),
        ),
      ),
      GoRoute(
        path: AppRoutes.schedule,
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) =>
            const AdaptivePage(child: ScheduleScreen()),
      ),
      GoRoute(
        path: AppRoutes.invite,
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => const AdaptivePage(child: InviteScreen()),
      ),
    ],
  );
}

/// Shown when a location does not match a route.
class NotFoundScreen extends StatelessWidget {
  const NotFoundScreen({super.key, required this.path});

  final String path;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'That page is not in the app.',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 8),
              Text(path, style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: () => context.go(AppRoutes.today),
                child: const Text('Go to today'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
