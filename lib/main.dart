import 'package:flutter/widgets.dart';
import 'package:pawsitive_sync/app.dart';
import 'package:pawsitive_sync/core/logging/app_log.dart';
import 'package:pawsitive_sync/data/care_repository.dart';
import 'package:pawsitive_sync/data/dose_reminders.dart';
import 'package:pawsitive_sync/data/household_api.dart';
import 'package:pawsitive_sync/data/reminder_choice.dart';
import 'package:pawsitive_sync/ui/onboarding/onboarding_view_model.dart';
import 'package:provider/provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  installErrorHandlers();
  await DoseReminders.prepare();
  final remindersOn = await ReminderChoice.read();
  const apiBase = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://pawsitive-api-production.up.railway.app',
  );
  final api = apiBase.isEmpty ? null : HouseholdApi(Uri.parse(apiBase));
  final care = CareRepository(api: api);
  final onboarding = OnboardingViewModel()..chooseReminders(remindersOn);
  AppLog.event('app.started', {'sync': api != null});
  if (api != null) {
    care.sync().then((_) {
      if (onboarding.remindersOn) DoseReminders.scheduleNext(care);
    });
  }
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
