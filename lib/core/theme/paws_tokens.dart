import 'package:flutter/material.dart';
import 'package:pawsitive_sync/core/theme/app_colors.dart';

double _lerpDouble(double a, double b, double t) => a + (b - a) * t;

/// A typography role that can be resolved into a [TextStyle] by the app theme.
///
/// Keeping the role's measurements here means screens do not need to invent a
/// new font size or line height when they introduce a new piece of UI.
@immutable
class PawsTypeStyle {
  const PawsTypeStyle({
    required this.fontSize,
    required this.height,
    required this.weight,
    this.letterSpacing = 0,
  });

  final double fontSize;
  final double height;
  final FontWeight weight;
  final double letterSpacing;

  TextStyle resolve({Color? color}) {
    return TextStyle(
      fontFamily: 'Geist',
      fontSize: fontSize,
      height: height,
      fontWeight: weight,
      letterSpacing: letterSpacing,
      color: color,
    );
  }

  PawsTypeStyle lerp(PawsTypeStyle other, double t) {
    return PawsTypeStyle(
      fontSize: _lerpDouble(fontSize, other.fontSize, t),
      height: _lerpDouble(height, other.height, t),
      weight: t < 0.5 ? weight : other.weight,
      letterSpacing: _lerpDouble(letterSpacing, other.letterSpacing, t),
    );
  }
}

/// Semantic text roles used to build [ThemeData.textTheme].
@immutable
class PawsTypography {
  const PawsTypography({
    required this.display,
    required this.headline,
    required this.section,
    required this.title,
    required this.subtitle,
    required this.label,
    required this.body,
    required this.bodySecondary,
    required this.caption,
    required this.labelSmall,
  });

  final PawsTypeStyle display;
  final PawsTypeStyle headline;
  final PawsTypeStyle section;
  final PawsTypeStyle title;
  final PawsTypeStyle subtitle;
  final PawsTypeStyle label;
  final PawsTypeStyle body;
  final PawsTypeStyle bodySecondary;
  final PawsTypeStyle caption;
  final PawsTypeStyle labelSmall;

  static const standard = PawsTypography(
    display: PawsTypeStyle(
      fontSize: 28,
      height: 1.15,
      weight: FontWeight.w600,
      letterSpacing: -0.6,
    ),
    headline: PawsTypeStyle(
      fontSize: 24,
      height: 1.2,
      weight: FontWeight.w600,
      letterSpacing: -0.4,
    ),
    section: PawsTypeStyle(
      fontSize: 20,
      height: 1.25,
      weight: FontWeight.w600,
      letterSpacing: -0.3,
    ),
    title: PawsTypeStyle(
      fontSize: 16,
      height: 1.3,
      weight: FontWeight.w600,
      letterSpacing: -0.1,
    ),
    subtitle: PawsTypeStyle(
      fontSize: 15,
      height: 1.3,
      weight: FontWeight.w600,
      letterSpacing: -0.1,
    ),
    label: PawsTypeStyle(fontSize: 14, height: 1.3, weight: FontWeight.w600),
    body: PawsTypeStyle(fontSize: 15, height: 1.4, weight: FontWeight.w400),
    bodySecondary: PawsTypeStyle(
      fontSize: 13,
      height: 1.35,
      weight: FontWeight.w400,
    ),
    caption: PawsTypeStyle(fontSize: 12, height: 1.35, weight: FontWeight.w400),
    labelSmall: PawsTypeStyle(
      fontSize: 11,
      height: 1.2,
      weight: FontWeight.w600,
      letterSpacing: 0.4,
    ),
  );

  PawsTypography lerp(PawsTypography other, double t) {
    return PawsTypography(
      display: display.lerp(other.display, t),
      headline: headline.lerp(other.headline, t),
      section: section.lerp(other.section, t),
      title: title.lerp(other.title, t),
      subtitle: subtitle.lerp(other.subtitle, t),
      label: label.lerp(other.label, t),
      body: body.lerp(other.body, t),
      bodySecondary: bodySecondary.lerp(other.bodySecondary, t),
      caption: caption.lerp(other.caption, t),
      labelSmall: labelSmall.lerp(other.labelSmall, t),
    );
  }
}

/// Spacing roles shared by pages, sections, controls and sheets.
@immutable
class PawsSpacing {
  const PawsSpacing({
    required this.xxs,
    required this.xs,
    required this.sm,
    required this.md,
    required this.lg,
    required this.xl,
    required this.xxl,
    required this.xxxl,
    required this.pageHorizontal,
    required this.pageTop,
    required this.pageBottom,
    required this.section,
    required this.controlGap,
    required this.inputHorizontal,
    required this.inputVertical,
  });

  final double xxs;
  final double xs;
  final double sm;
  final double md;
  final double lg;
  final double xl;
  final double xxl;
  final double xxxl;
  final double pageHorizontal;
  final double pageTop;
  final double pageBottom;
  final double section;
  final double controlGap;
  final double inputHorizontal;
  final double inputVertical;

  static const pageHorizontalValue = 24.0;
  static const pageTopValue = 20.0;
  static const pageBottomValue = 28.0;
  static const sectionValue = 24.0;
  static const mdValue = 12.0;
  static const lgValue = 16.0;
  static const xxlValue = 24.0;
  static const xxxlValue = 32.0;
  static const xsValue = 4.0;

  static const standard = PawsSpacing(
    xxs: 2,
    xs: 4,
    sm: 8,
    md: 12,
    lg: 16,
    xl: 20,
    xxl: 24,
    xxxl: 32,
    pageHorizontal: pageHorizontalValue,
    pageTop: pageTopValue,
    pageBottom: pageBottomValue,
    section: sectionValue,
    controlGap: 8,
    inputHorizontal: 16,
    inputVertical: 16,
  );

  PawsSpacing lerp(PawsSpacing other, double t) {
    return PawsSpacing(
      xxs: _lerpDouble(xxs, other.xxs, t),
      xs: _lerpDouble(xs, other.xs, t),
      sm: _lerpDouble(sm, other.sm, t),
      md: _lerpDouble(md, other.md, t),
      lg: _lerpDouble(lg, other.lg, t),
      xl: _lerpDouble(xl, other.xl, t),
      xxl: _lerpDouble(xxl, other.xxl, t),
      xxxl: _lerpDouble(xxxl, other.xxxl, t),
      pageHorizontal: _lerpDouble(pageHorizontal, other.pageHorizontal, t),
      pageTop: _lerpDouble(pageTop, other.pageTop, t),
      pageBottom: _lerpDouble(pageBottom, other.pageBottom, t),
      section: _lerpDouble(section, other.section, t),
      controlGap: _lerpDouble(controlGap, other.controlGap, t),
      inputHorizontal: _lerpDouble(inputHorizontal, other.inputHorizontal, t),
      inputVertical: _lerpDouble(inputVertical, other.inputVertical, t),
    );
  }
}

/// Corner-radius roles. The semantic names keep cards, controls and sheets
/// visually related while still allowing a one-off radius when the component
/// API explicitly supports it.
@immutable
class PawsRadii {
  const PawsRadii({
    required this.xs,
    required this.sm,
    required this.md,
    required this.lg,
    required this.xl,
    required this.xxl,
    required this.pill,
    required this.card,
    required this.input,
    required this.button,
    required this.chip,
    required this.sheet,
    required this.option,
  });

  final double xs;
  final double sm;
  final double md;
  final double lg;
  final double xl;
  final double xxl;
  final double pill;
  final double card;
  final double input;
  final double button;
  final double chip;
  final double sheet;
  final double option;

  static const cardValue = 16.0;

  static const standard = PawsRadii(
    xs: 4,
    sm: 8,
    md: 12,
    lg: 16,
    xl: 20,
    xxl: 28,
    pill: 999,
    card: cardValue,
    input: 12,
    button: 14,
    chip: 18,
    sheet: 28,
    option: 16,
  );

  BorderRadius get cardShape => BorderRadius.circular(card);

  BorderRadius get inputShape => BorderRadius.circular(input);

  BorderRadius get buttonShape => BorderRadius.circular(button);

  BorderRadius get chipShape => BorderRadius.circular(chip);

  BorderRadius get optionShape => BorderRadius.circular(option);

  BorderRadius get sheetShape =>
      BorderRadius.vertical(top: Radius.circular(sheet));

  PawsRadii lerp(PawsRadii other, double t) {
    return PawsRadii(
      xs: _lerpDouble(xs, other.xs, t),
      sm: _lerpDouble(sm, other.sm, t),
      md: _lerpDouble(md, other.md, t),
      lg: _lerpDouble(lg, other.lg, t),
      xl: _lerpDouble(xl, other.xl, t),
      xxl: _lerpDouble(xxl, other.xxl, t),
      pill: _lerpDouble(pill, other.pill, t),
      card: _lerpDouble(card, other.card, t),
      input: _lerpDouble(input, other.input, t),
      button: _lerpDouble(button, other.button, t),
      chip: _lerpDouble(chip, other.chip, t),
      sheet: _lerpDouble(sheet, other.sheet, t),
      option: _lerpDouble(option, other.option, t),
    );
  }
}

/// Minimum heights for tappable controls.
@immutable
class PawsControlHeights {
  const PawsControlHeights({
    required this.compact,
    required this.standard,
    required this.button,
    required this.input,
    required this.large,
    required this.chip,
    required this.icon,
    required this.listTile,
    required this.switchTrack,
    required this.switchThumb,
  });

  final double compact;
  final double standard;
  final double button;
  final double input;
  final double large;
  final double chip;
  final double icon;
  final double listTile;
  final double switchTrack;
  final double switchThumb;

  static const largeValue = 56.0;

  static const defaults = PawsControlHeights(
    compact: 40,
    standard: 48,
    button: 48,
    input: 56,
    large: largeValue,
    chip: 40,
    icon: 48,
    listTile: 56,
    switchTrack: 31,
    switchThumb: 27,
  );

  PawsControlHeights lerp(PawsControlHeights other, double t) {
    return PawsControlHeights(
      compact: _lerpDouble(compact, other.compact, t),
      standard: _lerpDouble(standard, other.standard, t),
      button: _lerpDouble(button, other.button, t),
      input: _lerpDouble(input, other.input, t),
      large: _lerpDouble(large, other.large, t),
      chip: _lerpDouble(chip, other.chip, t),
      icon: _lerpDouble(icon, other.icon, t),
      listTile: _lerpDouble(listTile, other.listTile, t),
      switchTrack: _lerpDouble(switchTrack, other.switchTrack, t),
      switchThumb: _lerpDouble(switchThumb, other.switchThumb, t),
    );
  }
}

/// Semantic surface fills. [ColorScheme] remains the source for standard
/// Material roles; these names cover app-specific surfaces and variants.
@immutable
class PawsSurfaces {
  const PawsSurfaces({
    required this.background,
    required this.card,
    required this.elevated,
    required this.subtle,
    required this.selected,
    required this.input,
    required this.inverse,
  });

  final Color background;
  final Color card;
  final Color elevated;
  final Color subtle;
  final Color selected;
  final Color input;
  final Color inverse;

  static const light = PawsSurfaces(
    background: AppColors.background,
    card: AppColors.white,
    elevated: AppColors.white,
    subtle: AppColors.neutral,
    selected: AppColors.brandSoft,
    input: AppColors.white,
    inverse: AppColors.ink,
  );

  static const dark = PawsSurfaces(
    background: AppColors.darkSurface,
    card: AppColors.darkCard,
    elevated: AppColors.darkCard,
    subtle: AppColors.darkNeutral,
    selected: AppColors.darkBrandSoft,
    input: AppColors.darkCard,
    inverse: AppColors.background,
  );

  PawsSurfaces lerp(PawsSurfaces other, double t) {
    return PawsSurfaces(
      background: Color.lerp(background, other.background, t)!,
      card: Color.lerp(card, other.card, t)!,
      elevated: Color.lerp(elevated, other.elevated, t)!,
      subtle: Color.lerp(subtle, other.subtle, t)!,
      selected: Color.lerp(selected, other.selected, t)!,
      input: Color.lerp(input, other.input, t)!,
      inverse: Color.lerp(inverse, other.inverse, t)!,
    );
  }
}

/// Semantic border colors, from decorative hairlines to interactive focus.
@immutable
class PawsBorders {
  const PawsBorders({
    required this.subtle,
    required this.standard,
    required this.strong,
    required this.focus,
    required this.error,
    required this.warning,
  });

  final Color subtle;
  final Color standard;
  final Color strong;
  final Color focus;
  final Color error;
  final Color warning;

  static const light = PawsBorders(
    subtle: AppColors.hairline,
    standard: AppColors.stroke,
    strong: AppColors.ink,
    focus: AppColors.brand,
    error: AppColors.error,
    warning: AppColors.warningBorder,
  );

  static const dark = PawsBorders(
    subtle: AppColors.darkHairline,
    standard: AppColors.darkStroke,
    strong: AppColors.darkInk,
    focus: AppColors.darkBrand,
    error: AppColors.error,
    warning: AppColors.darkWarningBorder,
  );

  PawsBorders lerp(PawsBorders other, double t) {
    return PawsBorders(
      subtle: Color.lerp(subtle, other.subtle, t)!,
      standard: Color.lerp(standard, other.standard, t)!,
      strong: Color.lerp(strong, other.strong, t)!,
      focus: Color.lerp(focus, other.focus, t)!,
      error: Color.lerp(error, other.error, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
    );
  }
}

/// Colors for selection, success, warnings, errors and disabled controls.
@immutable
class PawsSemanticStates {
  const PawsSemanticStates({
    required this.selected,
    required this.selectedContent,
    required this.success,
    required this.successContainer,
    required this.onSuccess,
    required this.warning,
    required this.warningContainer,
    required this.onWarning,
    required this.error,
    required this.errorContainer,
    required this.onError,
    required this.disabled,
    required this.disabledContent,
  });

  final Color selected;
  final Color selectedContent;
  final Color success;
  final Color successContainer;
  final Color onSuccess;
  final Color warning;
  final Color warningContainer;
  final Color onWarning;
  final Color error;
  final Color errorContainer;
  final Color onError;
  final Color disabled;
  final Color disabledContent;

  static const light = PawsSemanticStates(
    selected: AppColors.brandSoft,
    selectedContent: AppColors.brandDark,
    success: AppColors.brand,
    successContainer: AppColors.brandSoft,
    onSuccess: AppColors.white,
    warning: AppColors.warning,
    warningContainer: AppColors.warningBg,
    onWarning: AppColors.warning,
    error: AppColors.error,
    errorContainer: AppColors.errorContainer,
    onError: AppColors.white,
    disabled: Color(0x1F2C3531),
    disabledContent: Color(0x612C3531),
  );

  static const dark = PawsSemanticStates(
    selected: AppColors.darkBrandSoft,
    selectedContent: AppColors.darkBrand,
    success: AppColors.darkBrand,
    successContainer: AppColors.darkBrandSoft,
    onSuccess: AppColors.darkSurface,
    warning: AppColors.darkWarning,
    warningContainer: AppColors.darkWarningBg,
    onWarning: AppColors.darkWarning,
    error: AppColors.error,
    errorContainer: AppColors.errorContainer,
    onError: AppColors.white,
    disabled: Color(0x1FFFFFFF),
    disabledContent: Color(0x61F4F6F4),
  );

  PawsSemanticStates lerp(PawsSemanticStates other, double t) {
    return PawsSemanticStates(
      selected: Color.lerp(selected, other.selected, t)!,
      selectedContent: Color.lerp(selectedContent, other.selectedContent, t)!,
      success: Color.lerp(success, other.success, t)!,
      successContainer: Color.lerp(
        successContainer,
        other.successContainer,
        t,
      )!,
      onSuccess: Color.lerp(onSuccess, other.onSuccess, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      warningContainer: Color.lerp(
        warningContainer,
        other.warningContainer,
        t,
      )!,
      onWarning: Color.lerp(onWarning, other.onWarning, t)!,
      error: Color.lerp(error, other.error, t)!,
      errorContainer: Color.lerp(errorContainer, other.errorContainer, t)!,
      onError: Color.lerp(onError, other.onError, t)!,
      disabled: Color.lerp(disabled, other.disabled, t)!,
      disabledContent: Color.lerp(disabledContent, other.disabledContent, t)!,
    );
  }
}

/// Shared durations and curves. Context-aware reduced-motion handling remains
/// in [AppMotion]; this class is the source of its default measurements.
@immutable
class PawsMotion {
  const PawsMotion({
    required this.micro,
    required this.enter,
    required this.exit,
    required this.sheet,
    required this.page,
    required this.enterCurve,
    required this.exitCurve,
  });

  final Duration micro;
  final Duration enter;
  final Duration exit;
  final Duration sheet;
  final Duration page;
  final Curve enterCurve;
  final Curve exitCurve;

  static const microDuration = Duration(milliseconds: 120);
  static const enterDuration = Duration(milliseconds: 200);
  static const exitDuration = Duration(milliseconds: 140);
  static const sheetDuration = Duration(milliseconds: 200);
  static const pageDuration = Duration(milliseconds: 280);
  static const enterCurveValue = Curves.easeOutCubic;
  static const exitCurveValue = Curves.easeInCubic;

  static const standard = PawsMotion(
    micro: microDuration,
    enter: enterDuration,
    exit: exitDuration,
    sheet: sheetDuration,
    page: pageDuration,
    enterCurve: enterCurveValue,
    exitCurve: exitCurveValue,
  );

  PawsMotion lerp(PawsMotion other, double t) {
    // Motion values are discrete product decisions; switching halfway avoids
    // creating a duration that is not represented in the design system.
    return t < 0.5 ? this : other;
  }
}

/// Colors that sit outside [ColorScheme] roles plus the shared visual tokens.
@immutable
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
    this.typography = PawsTypography.standard,
    this.spacing = PawsSpacing.standard,
    this.radii = PawsRadii.standard,
    this.controlHeights = PawsControlHeights.defaults,
    this.surfaces = PawsSurfaces.light,
    this.borders = PawsBorders.light,
    this.motion = PawsMotion.standard,
    this.states = PawsSemanticStates.light,
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

  final PawsTypography typography;
  final PawsSpacing spacing;
  final PawsRadii radii;
  final PawsControlHeights controlHeights;
  final PawsSurfaces surfaces;
  final PawsBorders borders;
  final PawsMotion motion;
  final PawsSemanticStates states;

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
    surfaces: PawsSurfaces.light,
    borders: PawsBorders.light,
    states: PawsSemanticStates.light,
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
    surfaces: PawsSurfaces.dark,
    borders: PawsBorders.dark,
    states: PawsSemanticStates.dark,
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
    PawsTypography? typography,
    PawsSpacing? spacing,
    PawsRadii? radii,
    PawsControlHeights? controlHeights,
    PawsSurfaces? surfaces,
    PawsBorders? borders,
    PawsMotion? motion,
    PawsSemanticStates? states,
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
      typography: typography ?? this.typography,
      spacing: spacing ?? this.spacing,
      radii: radii ?? this.radii,
      controlHeights: controlHeights ?? this.controlHeights,
      surfaces: surfaces ?? this.surfaces,
      borders: borders ?? this.borders,
      motion: motion ?? this.motion,
      states: states ?? this.states,
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
      typography: typography.lerp(other.typography, t),
      spacing: spacing.lerp(other.spacing, t),
      radii: radii.lerp(other.radii, t),
      controlHeights: controlHeights.lerp(other.controlHeights, t),
      surfaces: surfaces.lerp(other.surfaces, t),
      borders: borders.lerp(other.borders, t),
      motion: motion.lerp(other.motion, t),
      states: states.lerp(other.states, t),
    );
  }
}

extension PawsTokensContext on BuildContext {
  PawsTokens get paws =>
      Theme.of(this).extension<PawsTokens>() ?? PawsTokens.light;
}
