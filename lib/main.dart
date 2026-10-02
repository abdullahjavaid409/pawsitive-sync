import 'package:flutter/widgets.dart';
import 'package:pawsitive_sync/app.dart';
import 'package:pawsitive_sync/core/logging/app_log.dart';
import 'package:pawsitive_sync/data/care_repository.dart';
import 'package:pawsitive_sync/data/dose_reminders.dart';
import 'package:pawsitive_sync/data/household_api.dart';
import 'package:pawsitive_sync/data/household_store.dart';
import 'package:pawsitive_sync/ui/onboarding/onboarding_view_model.dart';
import 'package:provider/provider.dart';

/// Pass `--dart-define=API_BASE_URL=` (empty) to run fully offline.
const _apiBase = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'https://pawsitive-api-production.up.railway.app',
);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  installErrorHandlers();
  await DoseReminders.prepare();
  final api = _apiBase.isEmpty ? null : HouseholdApi(Uri.parse(_apiBase));
  final care = CareRepository(api: api, store: HouseholdStore());
  await care.restore();
  final onboarding = await OnboardingViewModel.load();
  if (onboarding.isComplete && care.pets.isEmpty && !care.isConnected) {
    care.applyOnboarding(onboarding);
  }
  if (care.canSync || care.hasHousehold) care.sync();
  if (onboarding.isComplete && onboarding.remindersOn) {
    DoseReminders.scheduleNext(care);
  }
  AppLog.event('app.started', {
    'api': api != null,
    'connected': care.isConnected,
    'onboardingComplete': onboarding.isComplete,
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
