import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:pawsitive_sync/core/routing/app_shell.dart';
import 'package:pawsitive_sync/core/routing/routes.dart';
import 'package:pawsitive_sync/ui/household/household_screen.dart';
import 'package:pawsitive_sync/ui/household/invite_screen.dart';
import 'package:pawsitive_sync/ui/meds/medication_screen.dart';
import 'package:pawsitive_sync/ui/meds/schedule_screen.dart';
import 'package:pawsitive_sync/ui/onboarding/caregivers_screen.dart';
import 'package:pawsitive_sync/ui/onboarding/conditions_screen.dart';
import 'package:pawsitive_sync/ui/onboarding/notifications_screen.dart';
import 'package:pawsitive_sync/ui/onboarding/onboarding_view_model.dart';
import 'package:pawsitive_sync/ui/onboarding/pet_basics_screen.dart';
import 'package:pawsitive_sync/ui/onboarding/welcome_screen.dart';
import 'package:pawsitive_sync/ui/paywall/paywall_screen.dart';
import 'package:pawsitive_sync/ui/pets/pet_profile_screen.dart';
import 'package:pawsitive_sync/ui/reports/vet_report_screen.dart';
import 'package:pawsitive_sync/ui/today/lock_screen.dart';
import 'package:pawsitive_sync/ui/today/today_screen.dart';

GoRouter createRouter(OnboardingViewModel onboarding) {
  return GoRouter(
    initialLocation: AppRoutes.welcome,
    refreshListenable: onboarding,
    redirect: (context, state) {
      final location = state.matchedLocation;
      final open =
          location == AppRoutes.welcome ||
          location.startsWith('/onboarding') ||
          location == AppRoutes.paywall ||
          location == AppRoutes.lock;
      if (!onboarding.isComplete && !open) return AppRoutes.welcome;
      if (onboarding.isComplete &&
          (location == AppRoutes.welcome ||
              location.startsWith('/onboarding'))) {
        return AppRoutes.today;
      }
      return null;
    },
    errorBuilder: (context, state) =>
        NotFoundScreen(path: state.uri.toString()),
    routes: [
      GoRoute(
        path: AppRoutes.welcome,
        builder: (context, state) => const WelcomeScreen(),
      ),
      GoRoute(
        path: AppRoutes.pet,
        builder: (context, state) => const PetBasicsScreen(),
      ),
      GoRoute(
        path: AppRoutes.conditions,
        builder: (context, state) => const ConditionsScreen(),
      ),
      GoRoute(
        path: AppRoutes.caregivers,
        builder: (context, state) => const CaregiversScreen(),
      ),
      GoRoute(
        path: AppRoutes.notifications,
        builder: (context, state) => const NotificationsScreen(),
      ),
      GoRoute(
        path: AppRoutes.paywall,
        builder: (context, state) => const PaywallScreen(),
      ),
      GoRoute(
        path: AppRoutes.lock,
        builder: (context, state) => const LockScreen(),
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
        path: '/medication/:id',
        builder: (context, state) =>
            MedicationScreen(medicationId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: AppRoutes.schedule,
        builder: (context, state) => const ScheduleScreen(),
      ),
      GoRoute(
        path: AppRoutes.invite,
        builder: (context, state) => const InviteScreen(),
      ),
    ],
  );
}

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
