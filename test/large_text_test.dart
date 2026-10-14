import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pawsitive_sync/app.dart';
import 'package:pawsitive_sync/core/routing/routes.dart';
import 'package:pawsitive_sync/ui/onboarding/onboarding_view_model.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/app_fonts.dart';
import 'support/sample_household.dart';

/// The app follows the phone's text size up to 2x (lib/app.dart). Every main
/// screen must lay out and scroll at that size on a small phone without a
/// single overflow.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('every screen fits a 360 pt phone at 2x text', (tester) async {
    await loadAppFonts();
    final overflows = <String>{};
    var where = '';
    final previous = FlutterError.onError;
    FlutterError.onError = (details) {
      final message = details.exceptionAsString();
      if (message.contains('overflowed')) overflows.add('$where: $message');
      previous?.call(details);
    };
    addTearDown(() => FlutterError.onError = previous);
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    final onboarding = OnboardingViewModel()..finish(reminders: false);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(
            create: (_) => sampleCare(clock: () => DateTime(2026, 10, 3, 14)),
          ),
          ChangeNotifierProvider.value(value: onboarding),
        ],
        child: const PawsitiveApp(),
      ),
    );
    await tester.pumpAndSettle();
    final scaffold = tester.element(find.byType(Scaffold).first);
    expect(MediaQuery.textScalerOf(scaffold).scale(10), 20);

    final router = GoRouter.of(scaffold);
    for (final path in const [
      AppRoutes.today,
      AppRoutes.pets,
      AppRoutes.household,
      AppRoutes.reports,
      AppRoutes.schedule,
      AppRoutes.invite,
      AppRoutes.join,
      AppRoutes.addPet,
      '/edit-pet/miso',
      AppRoutes.settings,
      '/medication/insulin',
      AppRoutes.paywall,
    ]) {
      where = path;
      router.go(path);
      await tester.pumpAndSettle();
      for (var page = 0; page < 6; page++) {
        final scroll = find.byType(Scrollable);
        if (scroll.evaluate().isEmpty) break;
        await tester.drag(
          scroll.first,
          const Offset(0, -400),
          warnIfMissed: false,
        );
        await tester.pumpAndSettle();
      }
    }
    expect(overflows, isEmpty, reason: overflows.join('\n'));
  });
}
