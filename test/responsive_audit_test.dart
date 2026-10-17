import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pawsitive_sync/core/logging/app_log.dart';
import 'package:pawsitive_sync/core/routing/app_router.dart';
import 'package:pawsitive_sync/core/routing/routes.dart';
import 'package:pawsitive_sync/core/theme/app_theme.dart';
import 'package:pawsitive_sync/data/care_repository.dart';
import 'package:pawsitive_sync/ui/onboarding/onboarding_view_model.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/app_fonts.dart';
import 'support/sample_household.dart';

/// Every screen at every window class the app ships to: the smallest iPhone,
/// large text, a Pro Max, phone landscape, and iPad both ways. A screen
/// passes when it lays out and scrolls to the end with no overflow.
///
/// Set CAPTURE_DIR to also save one PNG per screen and scenario for review:
///   CAPTURE_DIR=/tmp/shots flutter test test/responsive_audit_test.dart
const _scenarios = [
  (name: 'se1', size: Size(320, 568), scale: 1.0, dark: false),
  (name: 'se1-2x', size: Size(320, 568), scale: 2.0, dark: false),
  (name: 'se3-1.3x', size: Size(375, 667), scale: 1.3, dark: false),
  (name: 'iphone-dark', size: Size(390, 844), scale: 1.0, dark: true),
  (name: 'promax', size: Size(440, 956), scale: 1.0, dark: false),
  (name: 'landscape', size: Size(844, 390), scale: 1.0, dark: false),
  (name: 'ipad', size: Size(1024, 1366), scale: 1.0, dark: false),
  (name: 'ipad-land', size: Size(1366, 1024), scale: 1.0, dark: true),
];

final _routes = <String>[
  AppRoutes.today,
  AppRoutes.pets,
  AppRoutes.household,
  AppRoutes.reports,
  AppRoutes.schedule,
  AppRoutes.medication('insulin'),
  AppRoutes.settings,
  AppRoutes.paywall,
  AppRoutes.invite,
  AppRoutes.join,
  AppRoutes.addPet,
  AppRoutes.editPet('miso'),
];

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppLog.enableTestCapture();
  });
  tearDown(AppLog.disableTestCapture);

  final captureDir = Platform.environment['CAPTURE_DIR'];

  for (final scenario in _scenarios) {
    testWidgets('every screen fits ${scenario.name}', (tester) async {
      final care = sampleCare(clock: () => DateTime(2026, 10, 3, 14));
      final router = await _pump(tester, care, scenario);
      for (final route in _routes) {
        router.go(route);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: '$route at top');
        if (captureDir != null) {
          await _capture(tester, captureDir, scenario.name, route);
        }
        await _scrollToEnd(tester, route);
      }
    });
  }
}

/// Drags the main vertical list until it stops moving, checking each page.
Future<void> _scrollToEnd(WidgetTester tester, String route) async {
  final lists = find.byWidgetPredicate(
    (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
  );
  if (lists.evaluate().isEmpty) return;
  final list = lists.first;
  for (var page = 0; page < 15; page++) {
    final position = tester.state<ScrollableState>(list).position;
    final before = position.pixels;
    await tester.drag(list, const Offset(0, -400), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: '$route page $page');
    if (position.pixels == before) break;
  }
}

Future<void> _capture(
  WidgetTester tester,
  String dir,
  String scenario,
  String route,
) async {
  final boundary =
      tester.renderObject(find.byKey(_shotKey)) as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    final name = route.replaceAll('/', '_').replaceAll(RegExp('^_'), '');
    final file = File('$dir/$scenario/${name.isEmpty ? 'root' : name}.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes!.buffer.asUint8List());
  });
}

const _shotKey = ValueKey('responsive-shot');

Future<GoRouter> _pump(
  WidgetTester tester,
  CareRepository care,
  ({String name, Size size, double scale, bool dark}) scenario,
) async {
  await loadAppFonts();
  tester.view.physicalSize = scenario.size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final model = OnboardingViewModel()..isComplete = true;
  final router = createRouter(model);
  await tester.pumpWidget(
    RepaintBoundary(
      key: _shotKey,
      child: MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: model),
          ChangeNotifierProvider.value(value: care),
        ],
        child: MaterialApp.router(
          theme: scenario.dark ? AppTheme.dark() : AppTheme.light(),
          routerConfig: router,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(scenario.scale),
              disableAnimations: true,
            ),
            child: child!,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    router.dispose();
    model.dispose();
    care.dispose();
  });
  return router;
}
