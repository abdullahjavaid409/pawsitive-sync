import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:pawsitive_sync/app.dart';
import 'package:pawsitive_sync/core/config/app_config.dart';
import 'package:pawsitive_sync/core/logging/app_log.dart';
import 'package:pawsitive_sync/data/care_repository.dart';
import 'package:pawsitive_sync/data/dose_reminders.dart';
import 'package:pawsitive_sync/data/engagement.dart';
import 'package:pawsitive_sync/data/household_api.dart';
import 'package:pawsitive_sync/data/household_store.dart';
import 'package:pawsitive_sync/data/pet_photo_store.dart';
import 'package:pawsitive_sync/data/push_service.dart';
import 'package:pawsitive_sync/data/reminders/reminder_background.dart';
import 'package:pawsitive_sync/data/revenue_cat_service.dart';
import 'package:pawsitive_sync/ui/onboarding/onboarding_view_model.dart';
import 'package:provider/provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  installErrorHandlers();
  runApp(await bootstrap());
}

/// Loads stored state and wires providers. Integration tests boot through here.
///
/// Only local disk reads are awaited before the first frame. Plugin setup and
/// every network call (RevenueCat, household sync) run in [_warmUp] after,
/// so a slow or missing connection never holds the launch screen.
Future<Widget> bootstrap() async {
  final launch = Stopwatch()..start();
  final api = AppConfig.hasApi
      ? HouseholdApi(Uri.parse(AppConfig.apiBaseUrl.trim()))
      : null;
  final care = CareRepository(
    api: api,
    store: HouseholdStore(),
    photoStore: PetPhotoStore(),
  );
  final engagement = EngagementState();
  var (_, onboarding, _) = await (
    care.restore(),
    OnboardingViewModel.load(),
    engagement.load(),
  ).wait;
  if (care.accountDeletePending) {
    // The app was killed mid-delete last time. Rare, so it is the one case
    // that waits on the network before the first frame: showing the deleted
    // household again would be worse. Success wipes; failure keeps the data.
    final error = await care.deleteAccount();
    if (error == null) onboarding = await OnboardingViewModel.load();
  }
  RevenueCatService.onEntitlementChanged = care.applyStoreEntitlement;
  if (onboarding.isComplete && care.pets.isEmpty && !care.isConnected) {
    care.applyOnboarding(onboarding);
  }
  AppLog.event('app.started', {
    ...AppConfig.summary,
    'connected': care.isConnected,
    'onboardingComplete': onboarding.isComplete,
    'ms': launch.elapsedMilliseconds,
  });
  // Household pushes: the reminder for a dose someone else gave is cancelled
  // by PushService; then refresh and re-aim the reminder. Also runs when iOS
  // wakes the app in the background for a silent push.
  PushService.onDosesLoggedElsewhere = (_) async {
    await care.sync(force: true, source: 'push');
    // Awaited (not left to the debounced listener): a background wake has
    // only ~30 s before iOS suspends the app again.
    await DoseReminders.reschedule(care, reason: 'push');
  };
  // Any change to doses, medicines or pets re-aims reminders (debounced).
  DoseReminders.attach(care);
  // Clock moved / zone changed while running (native signal) → re-plan.
  DoseReminders.listenToClock();
  engagement.update(care);
  care.addListener(() => engagement.update(care));
  PushService.listen();
  unawaited(_warmUp(care, onboarding));
  return MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: care),
      ChangeNotifierProvider.value(value: onboarding),
      ChangeNotifierProvider.value(value: engagement),
    ],
    child: const PawsitiveApp(),
  );
}

/// Post-launch work. Each step logs its own outcome and never throws.
Future<void> _warmUp(
  CareRepository care,
  OnboardingViewModel onboarding,
) async {
  final watch = Stopwatch()..start();
  try {
    // Local disk only: the rest of the 100-day history, before any sync.
    await care.loadRecentHistory();
    await Future.wait([
      DoseReminders.prepare(),
      () async {
        await RevenueCatService.initialize();
        // Identifies the store account, then reads the entitlement.
        await care.syncBillingFromStore();
      }(),
      if (care.isConnected) care.syncIfStale(),
      // APNs can hand out a new token after a restore or reinstall; this
      // only calls the server when the token or setting changed.
      if (care.isConnected) care.refreshPushRegistration(),
    ]);
    // A tap or "Given" that cold-started the app, now that data is loaded.
    await DoseReminders.handleLaunch();
    // After the sync, so reminders skip doses already given elsewhere.
    if (onboarding.isComplete) {
      await DoseReminders.reschedule(care, reason: 'launch');
    }
    // Re-plans while the app stays closed (the plan covers 7 days).
    unawaited(ReminderBackground.register());
    AppLog.event('app.warmed', {
      'ms': watch.elapsedMilliseconds,
      'billingRcReady': RevenueCatService.isReady,
      'isPro': care.isPro,
      'plan': care.plan.name,
    });
  } catch (error, stack) {
    AppLog.error('app.warm_up_failed', error, stack);
  }
}
