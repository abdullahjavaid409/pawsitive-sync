import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:pawsitive_sync/core/logging/app_log.dart';
import 'package:pawsitive_sync/core/routing/app_router.dart';
import 'package:pawsitive_sync/core/theme/app_theme.dart';
import 'package:pawsitive_sync/core/widgets/dismiss_keyboard.dart';
import 'package:pawsitive_sync/data/care_repository.dart';
import 'package:pawsitive_sync/data/apple_widgets.dart';
import 'package:pawsitive_sync/ui/onboarding/onboarding_view_model.dart';
import 'package:provider/provider.dart';

/// Applies the Pawsitive theme and router.
class PawsitiveApp extends StatefulWidget {
  const PawsitiveApp({super.key});

  @override
  State<PawsitiveApp> createState() => _PawsitiveAppState();
}

class _PawsitiveAppState extends State<PawsitiveApp> with WidgetsBindingObserver {
  GoRouter? _router;
  CareRepository? _widgetCare;

  void _refreshWidgets() {
    final care = _widgetCare;
    if (care != null) AppleWidgets.refresh(care);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _router ??= createRouter(context.read<OnboardingViewModel>());
    final care = context.read<CareRepository>();
    if (_widgetCare != care) {
      _widgetCare?.removeListener(_refreshWidgets);
      _widgetCare = care..addListener(_refreshWidgets);
      _refreshWidgets();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _widgetCare?.removeListener(_refreshWidgets);
    _router?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      AppLog.event('app.resumed');
      final care = context.read<CareRepository>();
      care.syncBillingFromStore();
      if (care.isConnected) care.syncIfStale();
      _refreshWidgets();
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Pawsitive',
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,
      routerConfig: _router,
      debugShowCheckedModeBanner: false,
      builder: (context, child) {
        final media = MediaQuery.of(context);
        return MediaQuery(
          data: media.copyWith(
            textScaler: media.textScaler.clamp(
              minScaleFactor: 1,
              maxScaleFactor: 1.15,
            ),
          ),
          child: DismissKeyboard(
            child: child ?? const SizedBox.shrink(),
          ),
        );
      },
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
