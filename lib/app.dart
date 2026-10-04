import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:pawsitive_sync/core/logging/app_log.dart';
import 'package:pawsitive_sync/core/routing/app_router.dart';
import 'package:pawsitive_sync/core/theme/app_colors.dart';
import 'package:pawsitive_sync/core/theme/app_theme.dart';
import 'package:pawsitive_sync/core/widgets/dismiss_keyboard.dart';
import 'package:pawsitive_sync/data/analytics_service.dart';
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

class _PawsitiveAppState extends State<PawsitiveApp>
    with WidgetsBindingObserver {
  GoRouter? _router;
  CareRepository? _widgetCare;

  bool _widgetsQueued = false;

  /// The repository notifies on every change (including sync start/finish);
  /// coalesce a burst into one widget snapshot per event-loop turn.
  void _refreshWidgets() {
    if (_widgetsQueued) return;
    _widgetsQueued = true;
    scheduleMicrotask(() {
      _widgetsQueued = false;
      final care = _widgetCare;
      if (care != null) {
        AppLog.unawaitedLogged(
          AppleWidgets.refresh(care),
          'widgets.update_failed',
        );
      }
    });
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
    final care = context.read<CareRepository>();
    if (state == AppLifecycleState.resumed) {
      AppLog.event('app.resumed');
      AppLog.unawaitedLogged(
        care.syncBillingFromStore(),
        'billing.sync.failed',
      );
      if (care.isConnected) {
        AppLog.unawaitedLogged(care.syncIfStale(), 'household.sync_failed');
      }
      _refreshWidgets();
    } else if (state == AppLifecycleState.paused) {
      // Finish the pending local save and send buffered funnel counts in one
      // call before iOS may suspend or kill the app.
      AppLog.event('app.paused');
      AppLog.unawaitedLogged(care.flushPersist(), 'store.flush_failed');
      AppLog.unawaitedLogged(
        AnalyticsService.flush(),
        'analytics.flush_failed',
      );
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
          child: DismissKeyboard(child: child ?? const SizedBox.shrink()),
        );
      },
    );
  }
}

/// Sends framework and platform errors to Flutter's error presenter.
/// Release builds show a calm fallback instead of the grey error box when a
/// widget fails to build; debug keeps Flutter's red screen for developers.
void installErrorHandlers() {
  if (kReleaseMode) {
    ErrorWidget.builder = (details) => const _ScreenErrorFallback();
  }
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

/// Shown in place of a widget that threw while building (release only).
/// The error itself is already logged by [FlutterError.onError].
class _ScreenErrorFallback extends StatelessWidget {
  const _ScreenErrorFallback();

  @override
  Widget build(BuildContext context) {
    return const Directionality(
      textDirection: TextDirection.ltr,
      child: ColoredBox(
        color: AppColors.background,
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Something went wrong on this screen — go back and try again.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Geist',
                fontSize: 16,
                height: 1.4,
                color: AppColors.ink,
                decoration: TextDecoration.none,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
