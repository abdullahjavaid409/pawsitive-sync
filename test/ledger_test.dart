import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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
  double width = 360,
  TextDirection direction = TextDirection.ltr,
}) async {
  await loadAppFonts();
  tester.view.physicalSize = Size(width, 780);
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
          size: Size(width, 780),
          textScaler: TextScaler.linear(textScale),
        ),
        child: Directionality(
          textDirection: direction,
          child: Scaffold(
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: child,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Every time label a ledger can show: 12h with one- and two-digit hours,
/// 24h, a locale-style meridiem, the trial-day labels and the empty dash.
const _times = [
  '8:00 AM',
  '11:51 PM',
  '12:45 PM',
  '23:59',
  '11:51 p.m.',
  'TODAY',
  'DAY 7',
  '—',
];

Widget _sheetOf(List<String> times) => LedgerSheet(
  children: [
    for (final (i, time) in times.indexed)
      LedgerLine(
        time: time,
        title: 'Carprofen · 1 tablet',
        detail: 'Biscuit · You',
        mark: LedgerMark.given,
        last: i == times.length - 1,
      ),
  ],
);

/// The gutter time paragraphs (the first text in each line).
List<RenderParagraph> _timeTexts(WidgetTester tester) => [
  for (final line in tester.elementList(find.byType(LedgerLine)))
    tester.renderObject<RenderParagraph>(
      find
          .descendant(
            of: find.byWidget(line.widget),
            matching: find.byType(RichText),
          )
          .first,
    ),
];

List<double> _gutterWidths(WidgetTester tester) => [
  for (final line in tester.elementList(find.byType(LedgerLine)))
    tester
        .getSize(
          find
              .descendant(
                of: find.byWidget(line.widget),
                matching: find.byType(SizedBox),
              )
              .first,
        )
        .width,
];

void main() {
  for (final width in [320.0, 390.0]) {
    for (final scale in [1.0, 1.3, 2.0]) {
      testWidgets('every time shows in full, ${width}pt at ${scale}x', (
        tester,
      ) async {
        await _pump(tester, _sheetOf(_times), textScale: scale, width: width);
        expect(tester.takeException(), isNull);
        for (final time in _timeTexts(tester)) {
          final label = time.text.toPlainText();
          expect(time.didExceedMaxLines, isFalse, reason: '$label clipped');
          // Wrapping is fine; shrinking the user's text size is not.
          expect(
            time.textScaler,
            TextScaler.linear(scale),
            reason: '$label was shrunk',
          );
        }
        // One margin rule down the whole sheet.
        expect(_gutterWidths(tester).toSet(), hasLength(1));
      });
    }
  }

  testWidgets('two-digit hours fit on one line at default text', (
    tester,
  ) async {
    await _pump(tester, _sheetOf(['10:00 AM', '11:51 PM', '12:45 PM']));
    for (final time in _timeTexts(tester)) {
      final oneLine = time.getMaxIntrinsicWidth(double.infinity);
      expect(
        oneLine,
        lessThanOrEqualTo(time.constraints.maxWidth),
        reason: '${time.text.toPlainText()} wrapped',
      );
    }
  });

  testWidgets('margin rule does not move between 9:59 and 10:00', (
    tester,
  ) async {
    await _pump(tester, _sheetOf(['9:59 AM']));
    final before = _gutterWidths(tester).single;
    await _pump(tester, _sheetOf(['10:00 AM']));
    expect(_gutterWidths(tester).single, before);
    expect(before, greaterThanOrEqualTo(ledgerGutter));
  });

  testWidgets('largest accessibility text shrinks a time, never clips', (
    tester,
  ) async {
    await _pump(tester, _sheetOf(_times), textScale: 3.1, width: 320);
    expect(tester.takeException(), isNull);
    // Capped so the title keeps most of the line.
    expect(_gutterWidths(tester).first, lessThanOrEqualTo((320 - 48) * 0.4));
    for (final time in _timeTexts(tester)) {
      expect(time.didExceedMaxLines, isFalse);
      expect(time.textScaler.scale(14), greaterThan(14));
    }
  });

  testWidgets('a tappable line is one VoiceOver button that taps', (
    tester,
  ) async {
    var taps = 0;
    final handle = tester.ensureSemantics();
    await _pump(
      tester,
      LedgerSheet(
        children: [
          LedgerLine(
            time: '8:00 AM',
            title: 'Carprofen',
            detail: 'Biscuit',
            stamp: 'YOU · 12:05 AM',
            mark: LedgerMark.given,
            onPressed: () => taps++,
          ),
          LedgerAddLine(label: 'Add medicine', onPressed: () => taps++),
        ],
      ),
    );
    expect(tester.takeException(), isNull);
    final line = find.bySemanticsLabel(
      '8:00 AM, Carprofen, Biscuit, YOU · 12:05 AM, done',
    );
    expect(line, findsOneWidget);
    expect(
      tester.getSemantics(line),
      matchesSemantics(
        label: '8:00 AM, Carprofen, Biscuit, YOU · 12:05 AM, done',
        isButton: true,
        hasTapAction: true,
      ),
    );
    final add = find.bySemanticsLabel('Add medicine');
    expect(
      tester.getSemantics(add),
      matchesSemantics(
        label: 'Add medicine',
        isButton: true,
        hasTapAction: true,
      ),
    );
    await tester.tap(find.text('Carprofen'));
    await tester.tap(find.text('Add medicine'));
    expect(taps, 2);
    // The whole line is at least a 48pt target.
    expect(
      tester.getSize(find.byType(LedgerAddLine)).height,
      greaterThanOrEqualTo(48),
    );
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(textContrastGuideline));
    handle.dispose();
  });

  testWidgets('the stamp fits beside a long pet name at 2x', (tester) async {
    await _pump(
      tester,
      const LedgerSheet(
        children: [
          LedgerLine(
            time: '11:51 PM',
            title: 'Phenobarbital oral suspension · 2.5 ml',
            detail: _longName,
            stamp: 'MAXIMILIANA · 11:51 PM',
            mark: LedgerMark.given,
          ),
        ],
      ),
      textScale: 2,
      width: 320,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('right-to-left puts the gutter on the right', (tester) async {
    await _pump(tester, _sheetOf(['11:51 PM']), direction: TextDirection.rtl);
    expect(tester.takeException(), isNull);
    final time = tester.getRect(find.text('11:51 PM'));
    final title = tester.getRect(find.text('Carprofen · 1 tablet'));
    expect(time.left, greaterThan(title.right));
  });

  testWidgets('a line outside a sheet sizes its own gutter', (tester) async {
    await _pump(
      tester,
      const LedgerLine(
        time: '11:51 PM',
        title: 'Carprofen',
        detail: 'Biscuit',
        mark: LedgerMark.given,
      ),
      textScale: 2,
    );
    expect(tester.takeException(), isNull);
    final time = _timeTexts(tester).single;
    expect(time.didExceedMaxLines, isFalse);
    expect(time.textScaler, const TextScaler.linear(2));
  });

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
