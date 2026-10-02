import 'package:flutter/widgets.dart';
import 'package:pawsitive_sync/app.dart';
import 'package:pawsitive_sync/core/config/app_config.dart';
import 'package:pawsitive_sync/core/logging/app_log.dart';
import 'package:pawsitive_sync/data/care_repository.dart';
import 'package:pawsitive_sync/data/dose_reminders.dart';
import 'package:pawsitive_sync/data/household_api.dart';
import 'package:pawsitive_sync/data/household_store.dart';
import 'package:pawsitive_sync/data/revenue_cat_service.dart';
import 'package:pawsitive_sync/ui/onboarding/onboarding_view_model.dart';
import 'package:provider/provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  installErrorHandlers();
  await DoseReminders.prepare();
  await RevenueCatService.initialize();
  final api = AppConfig.hasApi
      ? HouseholdApi(Uri.parse(AppConfig.apiBaseUrl.trim()))
      : null;
  final care = CareRepository(api: api, store: HouseholdStore());
  await care.restore();
  await RevenueCatService.identifyMember(care.memberId);
  await care.syncBillingFromStore();
  final onboarding = await OnboardingViewModel.load();
  if (onboarding.isComplete && care.pets.isEmpty && !care.isConnected) {
    care.applyOnboarding(onboarding);
  }
  if (care.isConnected) await care.syncIfStale();
  if (onboarding.isComplete && onboarding.remindersOn) {
    DoseReminders.scheduleNext(care);
  }
  AppLog.event('app.started', {
    ...AppConfig.summary,
    'connected': care.isConnected,
    'onboardingComplete': onboarding.isComplete,
    'billingRcReady': RevenueCatService.isReady,
    'isPro': care.isPro,
    'plan': care.plan.name,
  });
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: care),
        ChangeNotifierProvider.value(value: onboarding),
      ],
      child: const PawsitiveApp(),
    ),
  );
}
