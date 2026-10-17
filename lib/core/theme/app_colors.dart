import 'package:flutter/material.dart';

/// Magic Patterns v14 palette: cream cards on oat paper, espresso ink and a
/// warm clay action colour (5.6:1 with cream text). Dark mode is the same
/// family at night: roasted brown surfaces, a lighter clay for contrast.
/// Green is a status color for a given dose, never the brand.
abstract final class AppColors {
  static const background = Color(0xFFF4EDE2);
  static const paper = Color(0xFFFFFCF7);
  static const ink = Color(0xFF2A211B);
  static const muted = Color(0xFF6F6357);
  static const body = Color(0xFF453830);
  static const brand = Color(0xFFA4502F);
  static const brandDark = Color(0xFF8A4126);
  static const brandSoft = Color(0xFFF5E4D9);
  static const brandPressed = Color(0xFF73351F);
  static const white = Color(0xFFFFFFFF);
  static const hairline = Color(0xFFE6DACA);
  static const divider = Color(0xFFEFE6D8);
  static const neutral = Color(0xFFEDE3D4);
  static const stroke = Color(0xFFC9BBA8);
  static const emptyStroke = Color(0xFFC4B8AA);
  static const warningBg = Color(0xFFFBEBCF);
  static const warningBorder = Color(0xFFEBC98A);
  static const warning = Color(0xFF8A5A10);
  static const warningIcon = Color(0xFF8F5A00);
  static const amber = Color(0xFFF2B04C);
  static const given = Color(0xFF17663A);
  static const givenSoft = Color(0xFFE2F0E6);
  static const unsure = Color(0xFF4F4339);
  static const unsureBg = Color(0xFFEDE3D4);
  static const lock = Color(0xFF2A211B);
  static const scrim = Color(0x732A211B);

  static const darkSurface = Color(0xFF16110D);
  static const darkCard = Color(0xFF221B16);
  static const darkInk = Color(0xFFF4ECE0);
  static const darkMuted = Color(0xFFB5A898);
  static const darkHairline = Color(0xFF3A2F27);
  static const darkNeutral = Color(0xFF2F2620);
  static const darkBrandSoft = Color(0xFF41271B);
  static const darkOnPrimaryContainer = Color(0xFFF3BFA4);
  static const darkStroke = Color(0xFF5C4E43);
  static const darkDivider = Color(0xFF2C231D);
  static const darkWarning = Color(0xFFF2B04C);
  static const darkWarningBorder = Color(0xFF5A4520);
  static const darkWarningBg = Color(0xFF2E2410);
  static const darkBrand = Color(0xFFE59570);
  static const darkOnBrand = Color(0xFF2A1208);
  static const darkGiven = Color(0xFF5CC98A);
  static const darkOnGiven = Color(0xFF0B2416);
  static const darkGivenSoft = Color(0xFF173323);
  static const darkUnsure = Color(0xFFCBBDAD);
  static const darkUnsureBg = Color(0xFF2F2620);
  static const error = Color(0xFFB42318);
  static const errorContainer = Color(0xFFF8E4E2);
  static const onErrorContainer = Color(0xFF7A1D16);
  static const darkError = Color(0xFFFF8A80);

  /// Muted ring on an upcoming schedule stop.
  static const timelineMuted = Color(0xFFA89A8A);

  /// Lock-screen preview wallpaper and its progress fill.
  static const lockWallpaper = Color(0xFF2A1D16);
  static const lockProgress = Color(0xFFE59570);

  /// Translucent surfaces used only on the lock screen.
  static const lockDate = Color(0xBFFFFFFF);
  static const lockCard = Color(0xF0FFFDF8);
  static const lockHistory = Color(0xCCFFFDF8);
  static const lockHandle = Color(0xCCFFFFFF);
}
