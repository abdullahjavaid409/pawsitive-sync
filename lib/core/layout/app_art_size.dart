import 'package:flutter/material.dart';

double _shortestSide(BuildContext context) =>
    MediaQuery.sizeOf(context).shortestSide;

/// Large hero art for welcome and empty states.
double appHeroArtSize(BuildContext context) {
  final side = _shortestSide(context);
  if (side >= 820) return 256;
  if (side >= 680) return 232;
  return 208;
}

/// Step illustrations during onboarding.
double appOnboardingArtSize(BuildContext context) {
  final side = _shortestSide(context);
  if (side >= 820) return 240;
  if (side >= 680) return 220;
  return 200;
}

/// Species mark beside onboarding art.
double appOnboardingMarkSize(BuildContext context) {
  return (appOnboardingArtSize(context) * 0.34).clamp(64, 88);
}

/// Empty Today tab and sheet moments.
double appEmptyStateArtSize(BuildContext context) {
  final side = _shortestSide(context);
  if (side >= 820) return 220;
  if (side >= 680) return 200;
  return 180;
}

/// Morning/afternoon/evening section labels.
double appPartArtSize(BuildContext context) {
  final side = _shortestSide(context);
  if (side >= 820) return 52;
  if (side >= 680) return 48;
  return 44;
}

/// Inline banners such as low-supply or sync status.
double appInlineArtSize(BuildContext context) {
  final side = _shortestSide(context);
  if (side >= 820) return 56;
  if (side >= 680) return 52;
  return 48;
}

/// Pet mark on dose cards.
double appPetMarkSize(BuildContext context, {double compact = 56}) {
  final side = _shortestSide(context);
  if (side >= 820) return compact + 16;
  if (side >= 680) return compact + 8;
  return compact;
}
