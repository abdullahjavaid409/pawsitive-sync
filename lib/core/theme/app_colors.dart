import 'package:flutter/material.dart';

/// Gave It palette: Ink & Paper in light, Midnight in dark
/// (docs/REDESIGN_GAVE_IT.md, redesign E).
/// Green is a status color for a given dose, never the brand.
abstract final class AppColors {
  static const background = Color(0xFFF3F0EA);
  static const paper = Color(0xFFFFFFFF);
  static const ink = Color(0xFF1A1C24);
  static const muted = Color(0xFF5E5A52);
  static const body = Color(0xFF3B3934);
  static const brand = Color(0xFF2638C4);
  static const brandDark = Color(0xFF1E2C9E);
  static const brandSoft = Color(0xFFE4E7FB);
  static const brandPressed = Color(0xFF16227A);
  static const white = Color(0xFFFFFFFF);
  static const hairline = Color(0xFFD9D2C3);
  static const divider = Color(0xFFEAE4D7);
  static const neutral = Color(0xFFEDE7DB);
  static const stroke = Color(0xFFBFB6A4);
  static const emptyStroke = Color(0xFFCFC7B6);
  static const warningBg = Color(0xFFFBEBCF);
  static const warningBorder = Color(0xFFEBC98A);
  static const warning = Color(0xFF7A4A00);
  static const warningIcon = Color(0xFF8F5A00);
  static const amber = Color(0xFFF2B04C);
  static const given = Color(0xFF17663A);
  static const givenSoft = Color(0xFFE2F0E6);
  static const unsure = Color(0xFF3F4A5C);
  static const unsureBg = Color(0xFFE9ECF1);
  static const lock = Color(0xFF1A1C24);
  static const scrim = Color(0x731A1C24);

  static const darkSurface = Color(0xFF0E1116);
  static const darkCard = Color(0xFF181C24);
  static const darkInk = Color(0xFFF2EEE6);
  static const darkMuted = Color(0xFFA7A196);
  static const darkHairline = Color(0xFF2C2F38);
  static const darkNeutral = Color(0xFF22252D);
  static const darkBrandSoft = Color(0xFF232A5C);
  static const darkOnPrimaryContainer = Color(0xFFB8C0FF);
  static const darkStroke = Color(0xFF4A4E5A);
  static const darkDivider = Color(0xFF24272F);
  static const darkWarning = Color(0xFFF2B04C);
  static const darkWarningBorder = Color(0xFF5A4520);
  static const darkWarningBg = Color(0xFF2E2410);
  static const darkBrand = Color(0xFF8F9CFF);
  static const darkOnBrand = Color(0xFF0E1240);
  static const darkGiven = Color(0xFF5CC98A);
  static const darkOnGiven = Color(0xFF0B2416);
  static const darkGivenSoft = Color(0xFF173323);
  static const darkUnsure = Color(0xFFB4BDCC);
  static const darkUnsureBg = Color(0xFF232833);
  static const error = Color(0xFFB42318);
  static const errorContainer = Color(0xFFF8E4E2);
  static const onErrorContainer = Color(0xFF7A1D16);
  static const darkError = Color(0xFFFF8A80);

  /// Muted ring on an upcoming schedule stop.
  static const timelineMuted = Color(0xFFA39E94);

  /// Lock-screen preview wallpaper and its progress fill.
  static const lockWallpaper = Color(0xFF10163F);
  static const lockProgress = Color(0xFF8F9CFF);

  /// Translucent surfaces used only on the lock screen.
  static const lockDate = Color(0xBFFFFFFF);
  static const lockCard = Color(0xF0FFFDF8);
  static const lockHistory = Color(0xCCFFFDF8);
  static const lockHandle = Color(0xCCFFFFFF);
}
