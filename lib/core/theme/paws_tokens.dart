import 'package:flutter/material.dart';
import 'package:pawsitive_sync/core/theme/app_colors.dart';

/// Colors that sit outside [ColorScheme] roles.
class PawsTokens extends ThemeExtension<PawsTokens> {
  const PawsTokens({
    required this.warning,
    required this.onWarning,
    required this.warningBorder,
    required this.warningBg,
    required this.warningIcon,
    required this.amber,
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
  final Color warningIcon;
  final Color amber;
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
    warningIcon: AppColors.warningIcon,
    amber: AppColors.amber,
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
    warning: AppColors.darkWarning,
    onWarning: AppColors.darkWarning,
    warningBorder: AppColors.darkWarningBorder,
    warningBg: AppColors.darkWarningBg,
    warningIcon: AppColors.darkWarning,
    amber: AppColors.amber,
    brandDark: AppColors.darkBrand,
    brandSoft: AppColors.darkBrandSoft,
    neutral: AppColors.darkNeutral,
    stroke: AppColors.darkStroke,
    hairline: AppColors.darkHairline,
    divider: AppColors.darkDivider,
    card: AppColors.darkCard,
    lock: AppColors.lock,
  );

  @override
  PawsTokens copyWith({
    Color? warning,
    Color? onWarning,
    Color? warningBorder,
    Color? warningBg,
    Color? warningIcon,
    Color? amber,
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
      warningIcon: warningIcon ?? this.warningIcon,
      amber: amber ?? this.amber,
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
      warningIcon: Color.lerp(warningIcon, other.warningIcon, t)!,
      amber: Color.lerp(amber, other.amber, t)!,
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
