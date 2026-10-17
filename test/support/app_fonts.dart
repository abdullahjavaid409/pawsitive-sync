import 'dart:io';

import 'package:flutter/services.dart';

/// Loads real fonts so widget tests measure real text widths (the default
/// test font is a fixed-width box face).
///
/// The app bundles its body font (Figtree). The system proxy names are
/// still mapped to a stand-in for any widget that asks for them directly.
Future<void> loadAppFonts() async {
  const families = {
    'Instrument Serif': [
      'assets/fonts/InstrumentSerif-Regular.ttf',
      'assets/fonts/InstrumentSerif-Italic.ttf',
    ],
    'Figtree': [
      'assets/fonts/Figtree-Regular.ttf',
      'assets/fonts/Figtree-Medium.ttf',
      'assets/fonts/Figtree-SemiBold.ttf',
      'assets/fonts/Figtree-Bold.ttf',
    ],
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
