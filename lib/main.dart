import 'package:flutter/widgets.dart';
import 'package:pawsitive_sync/app.dart';
import 'package:pawsitive_sync/data/care_repository.dart';
import 'package:pawsitive_sync/ui/onboarding/onboarding_view_model.dart';
import 'package:provider/provider.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  installErrorHandlers();
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => CareRepository()),
        ChangeNotifierProvider(create: (_) => OnboardingViewModel()),
      ],
      child: const PawsitiveApp(),
    ),
  );
}
