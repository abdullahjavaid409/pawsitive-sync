import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pawsitive_sync/core/theme/app_theme.dart';
import 'package:pawsitive_sync/core/widgets/ledger.dart';

import 'support/app_fonts.dart';

const _longName = 'Maximiliana Alexandrina Featherstonehaugh-Worthington';

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  double textScale = 1,
  bool dark = false,
}) async {
  await loadAppFonts();
  tester.view.physicalSize = const Size(360, 780);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: dark ? ThemeMode.dark : ThemeMode.light,
      home: MediaQuery(
        data: MediaQueryData(
          size: const Size(360, 780),
          textScaler: TextScaler.linear(textScale),
        ),
        child: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: child,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  for (final scale in [1.0, 1.3, 2.0]) {
    for (final dark in [false, true]) {
      testWidgets('ledger lines fit at ${scale}x text, dark=$dark', (
        tester,
      ) async {
        await _pump(
          tester,
          const LedgerSheet(
            children: [
              LedgerLine(
                time: '12:45 PM',
                title: 'Phenobarbital oral suspension · 2.5 ml',
                detail: 'Biscuit · $_longName',
                mark: LedgerMark.given,
              ),
              LedgerLine(
                time: '8:00 AM',
                title: 'Insulin',
                detail: 'Miso · not sure if given',
                mark: LedgerMark.unsure,
              ),
              LedgerLine(
                time: '',
                title: '',
                detail: '',
                mark: LedgerMark.due,
                last: true,
              ),
            ],
          ),
          textScale: scale,
          dark: dark,
        );
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('stamp truncates a long name at ${scale}x text', (
      tester,
    ) async {
      await _pump(
        tester,
        const Center(
          child: GivenStamp(who: _longName, time: '8:02 AM'),
        ),
        textScale: scale,
      );
      expect(tester.takeException(), isNull);
      expect(find.text('ALREADY GIVEN'), findsOneWidget);
      final stamp = tester.getSize(find.byType(GivenStamp));
      expect(stamp.width, lessThanOrEqualTo(360));
    });
  }

  testWidgets('stamp reads out who and when to screen readers', (tester) async {
    await _pump(tester, const GivenStamp(who: 'Sara', time: '8:02 AM'));
    expect(
      find.bySemanticsLabel('Already given by Sara at 8:02 AM'),
      findsOneWidget,
    );
  });

  for (final (given, due, total) in [
    (0, 0, 0),
    (5, 2, 4),
    (-1, -3, 3),
    (10, 10, 40),
  ]) {
    testWidgets('strip survives given=$given due=$due total=$total', (
      tester,
    ) async {
      await _pump(
        tester,
        LedgerStrip(given: given, due: due, total: total),
        textScale: 2,
      );
      expect(tester.takeException(), isNull);
      expect(find.byType(LedgerMarkBox), findsNWidgets(total < 0 ? 0 : total));
    });
  }

  testWidgets('Gave it button is disabled without an action', (tester) async {
    await _pump(tester, const GaveItButton(label: 'Gave it', onPressed: null));
    expect(tester.takeException(), isNull);
    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.onPressed, isNull);
  });
}
