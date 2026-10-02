import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:pawsitive_sync/core/logging/app_log.dart';
import 'package:pawsitive_sync/core/routing/app_router.dart';
import 'package:pawsitive_sync/core/theme/app_theme.dart';
import 'package:pawsitive_sync/ui/onboarding/onboarding_view_model.dart';
import 'package:provider/provider.dart';

/// Applies the PawsitiveSync theme and router.
class PawsitiveApp extends StatefulWidget {
  const PawsitiveApp({super.key});

  @override
  State<PawsitiveApp> createState() => _PawsitiveAppState();
}

class _PawsitiveAppState extends State<PawsitiveApp> {
  GoRouter? _router;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _router ??= createRouter(context.read<OnboardingViewModel>());
  }

  @override
  void dispose() {
    _router?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'PawsitiveSync',
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,
      routerConfig: _router,
      debugShowCheckedModeBanner: false,
    );
  }
}

/// Sends framework and platform errors to Flutter's error presenter.
void installErrorHandlers() {
  FlutterError.onError = (details) {
    AppLog.error('flutter.error', details.exception, details.stack);
    FlutterError.presentError(details);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    AppLog.error('platform.error', error, stack);
    FlutterError.presentError(
      FlutterErrorDetails(exception: error, stack: stack),
    );
    return true;
  };
}
