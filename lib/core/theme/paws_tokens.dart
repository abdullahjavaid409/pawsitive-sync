import 'package:flutter/material.dart';
import 'package:pawsitive_sync/core/theme/app_colors.dart';

/// Colors that sit outside [ColorScheme] roles.
class PawsTokens extends ThemeExtension<PawsTokens> {
  const PawsTokens({
    required this.warning,
    required this.onWarning,
    required this.warningBorder,
    required this.warningBg,
    required this.brandDark,
    required this.brandSoft,
    required this.neutral,
    required this.stroke,
    required this.hairline,
    required this.divider,
    required this.card,
    required this.lock,
  });

  final Color warning;
  final Color onWarning;
  final Color warningBorder;
  final Color warningBg;
  final Color brandDark;
  final Color brandSoft;
  final Color neutral;
  final Color stroke;
  final Color hairline;
  final Color divider;
  final Color card;
  final Color lock;

  static const light = PawsTokens(
    warning: AppColors.warning,
    onWarning: AppColors.warning,
    warningBorder: AppColors.warningBorder,
    warningBg: AppColors.warningBg,
    brandDark: AppColors.brandDark,
    brandSoft: AppColors.brandSoft,
    neutral: AppColors.neutral,
    stroke: AppColors.stroke,
    hairline: AppColors.hairline,
    divider: AppColors.divider,
    card: AppColors.white,
    lock: AppColors.lock,
  );

  static const dark = PawsTokens(
    warning: Color(0xFFE8C48A),
    onWarning: Color(0xFFE8C48A),
    warningBorder: Color(0xFF6B5430),
    warningBg: Color(0xFF3A2E1C),
    brandDark: Color(0xFF8FBF9C),
    brandSoft: AppColors.darkBrandSoft,
    neutral: AppColors.darkNeutral,
    stroke: Color(0xFF5C6560),
    hairline: AppColors.darkHairline,
    divider: Color(0xFF2A332F),
    card: AppColors.darkCard,
    lock: AppColors.lock,
  );

  @override
  PawsTokens copyWith({
    Color? warning,
    Color? onWarning,
    Color? warningBorder,
    Color? warningBg,
    Color? brandDark,
    Color? brandSoft,
    Color? neutral,
    Color? stroke,
    Color? hairline,
    Color? divider,
    Color? card,
    Color? lock,
  }) {
    return PawsTokens(
      warning: warning ?? this.warning,
      onWarning: onWarning ?? this.onWarning,
      warningBorder: warningBorder ?? this.warningBorder,
      warningBg: warningBg ?? this.warningBg,
      brandDark: brandDark ?? this.brandDark,
      brandSoft: brandSoft ?? this.brandSoft,
      neutral: neutral ?? this.neutral,
      stroke: stroke ?? this.stroke,
      hairline: hairline ?? this.hairline,
      divider: divider ?? this.divider,
      card: card ?? this.card,
      lock: lock ?? this.lock,
    );
  }

  @override
  PawsTokens lerp(ThemeExtension<PawsTokens>? other, double t) {
    if (other is! PawsTokens) return this;
    return PawsTokens(
      warning: Color.lerp(warning, other.warning, t)!,
      onWarning: Color.lerp(onWarning, other.onWarning, t)!,
      warningBorder: Color.lerp(warningBorder, other.warningBorder, t)!,
      warningBg: Color.lerp(warningBg, other.warningBg, t)!,
      brandDark: Color.lerp(brandDark, other.brandDark, t)!,
      brandSoft: Color.lerp(brandSoft, other.brandSoft, t)!,
      neutral: Color.lerp(neutral, other.neutral, t)!,
      stroke: Color.lerp(stroke, other.stroke, t)!,
      hairline: Color.lerp(hairline, other.hairline, t)!,
      divider: Color.lerp(divider, other.divider, t)!,
      card: Color.lerp(card, other.card, t)!,
      lock: Color.lerp(lock, other.lock, t)!,
    );
  }
}

extension PawsTokensContext on BuildContext {
  PawsTokens get paws => Theme.of(this).extension<PawsTokens>()!;
}
