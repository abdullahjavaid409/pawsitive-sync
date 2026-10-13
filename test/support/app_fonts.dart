import 'package:flutter/services.dart';

/// Loads the bundled app fonts so widget tests measure real text widths
/// (the default test font is a fixed-width box face).
Future<void> loadAppFonts() async {
  const families = {
    'Bricolage Grotesque': [
      'BricolageGrotesque-SemiBold',
      'BricolageGrotesque-Bold',
    ],
    'Atkinson Hyperlegible': [
      'AtkinsonHyperlegibleNext-Regular',
      'AtkinsonHyperlegibleNext-SemiBold',
      'AtkinsonHyperlegibleNext-Bold',
    ],
    'Atkinson Hyperlegible Mono': ['AtkinsonHyperlegibleMono-Medium'],
  };
  for (final MapEntry(key: family, value: files) in families.entries) {
    final loader = FontLoader(family);
    for (final file in files) {
      loader.addFont(rootBundle.load('assets/fonts/$file.ttf'));
    }
    await loader.load();
  }
}
