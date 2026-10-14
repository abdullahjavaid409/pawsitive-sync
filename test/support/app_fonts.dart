import 'dart:io';

import 'package:flutter/services.dart';

/// Loads real fonts so widget tests measure real text widths (the default
/// test font is a fixed-width box face).
///
/// The app's body text is the system font (SF Pro on iOS), which the test
/// host can't load, so Atkinson Hyperlegible Next stands in for it under the
/// same proxy names; its widths are close to SF Pro Text's.
Future<void> loadAppFonts() async {
  const families = {
    'Instrument Serif': ['assets/fonts/InstrumentSerif-Regular.ttf'],
    'Atkinson Hyperlegible Mono': [
      'assets/fonts/AtkinsonHyperlegibleMono-Medium.ttf',
    ],
    'CupertinoSystemText': _systemStandIn,
    'CupertinoSystemDisplay': _systemStandIn,
  };
  for (final MapEntry(key: family, value: files) in families.entries) {
    final loader = FontLoader(family);
    for (final file in files) {
      loader.addFont(_load(file));
    }
    await loader.load();
  }
}

const _systemStandIn = [
  'test/fixtures/fonts/AtkinsonHyperlegibleNext-Regular.ttf',
  'test/fixtures/fonts/AtkinsonHyperlegibleNext-SemiBold.ttf',
  'test/fixtures/fonts/AtkinsonHyperlegibleNext-Bold.ttf',
];

// Synchronous on purpose: async file I/O never completes inside
// testWidgets' fake-async zone, which would hang every widget test.
Future<ByteData> _load(String path) =>
    Future.value(ByteData.sublistView(File(path).readAsBytesSync()));
