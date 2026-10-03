import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:pawsitive_sync/core/theme/app_colors.dart';
import 'package:pawsitive_sync/core/theme/paws_tokens.dart';

/// Light and dark themes built from the shared PawsitiveSync palette.
abstract final class AppTheme {
  static ThemeData light() => _build(Brightness.light);

  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isLight = brightness == Brightness.light;
    final tokens = isLight ? PawsTokens.light : PawsTokens.dark;
    final surfaces = tokens.surfaces;
    final borders = tokens.borders;
    final states = tokens.states;
    final spacing = tokens.spacing;
    final radii = tokens.radii;
    final heights = tokens.controlHeights;
    final scheme = ColorScheme(
      brightness: brightness,
      primary: AppColors.brand,
      onPrimary: AppColors.white,
      primaryContainer: isLight ? AppColors.brandSoft : AppColors.darkBrandSoft,
      onPrimaryContainer: isLight
          ? AppColors.brandDark
          : AppColors.darkOnPrimaryContainer,
      secondary: AppColors.ink,
      onSecondary: AppColors.white,
      secondaryContainer: isLight ? AppColors.neutral : AppColors.darkNeutral,
      onSecondaryContainer: isLight ? AppColors.ink : AppColors.darkInk,
      error: states.error,
      onError: states.onError,
      errorContainer: states.errorContainer,
      onErrorContainer: AppColors.onErrorContainer,
      surface: surfaces.background,
      onSurface: isLight ? AppColors.ink : AppColors.darkInk,
      onSurfaceVariant: isLight ? AppColors.muted : AppColors.darkMuted,
      outline: borders.standard,
      outlineVariant: borders.subtle,
      shadow: AppColors.ink,
      scrim: AppColors.scrim,
      inverseSurface: surfaces.inverse,
      onInverseSurface: isLight ? AppColors.background : AppColors.ink,
      inversePrimary: AppColors.brandSoft,
      surfaceTint: Colors.transparent,
      surfaceContainerLowest: surfaces.card,
      surfaceContainerLow: surfaces.background,
      surfaceContainer: surfaces.subtle,
      surfaceContainerHigh: isLight ? AppColors.divider : AppColors.darkDivider,
      surfaceContainerHighest: borders.subtle,
    );

    final base = isLight
        ? ThemeData.light().textTheme
        : ThemeData.dark().textTheme;
    final geist = base.apply(
      fontFamily: 'Geist',
      bodyColor: scheme.onSurface,
      displayColor: scheme.onSurface,
    );
    TextStyle role(TextStyle? source, PawsTypeStyle token, {Color? color}) {
      return (source ?? const TextStyle()).copyWith(
        fontFamily: 'Geist',
        fontSize: token.fontSize,
        height: token.height,
        fontWeight: token.weight,
        letterSpacing: token.letterSpacing,
        color: color,
      );
    }

    final typography = tokens.typography;
    final text = geist.copyWith(
      displaySmall: role(
        geist.displaySmall,
        typography.display,
        color: scheme.onSurface,
      ),
      headlineMedium: role(
        geist.headlineMedium,
        typography.headline,
        color: scheme.onSurface,
      ),
      headlineSmall: role(
        geist.headlineSmall,
        typography.section,
        color: scheme.onSurface,
      ),
      titleLarge: role(
        geist.titleLarge,
        typography.title,
        color: scheme.onSurface,
      ),
      titleMedium: role(
        geist.titleMedium,
        typography.subtitle,
        color: scheme.onSurface,
      ),
      titleSmall: role(
        geist.titleSmall,
        typography.label,
        color: scheme.onSurface,
      ),
      bodyLarge: role(
        geist.bodyLarge,
        typography.body,
        color: scheme.onSurface,
      ),
      bodyMedium: role(
        geist.bodyMedium,
        typography.bodySecondary,
        color: scheme.onSurfaceVariant,
      ),
      bodySmall: role(
        geist.bodySmall,
        typography.caption,
        color: scheme.onSurfaceVariant,
      ),
      labelLarge: role(geist.labelLarge, typography.label),
      labelSmall: role(
        geist.labelSmall,
        typography.labelSmall,
        color: scheme.onSurfaceVariant,
      ),
    );

    final buttonShape = RoundedRectangleBorder(borderRadius: radii.buttonShape);
    final inputBorder = OutlineInputBorder(
      borderRadius: radii.inputShape,
      borderSide: BorderSide(color: borders.subtle),
    );
    final focusedInputBorder = OutlineInputBorder(
      borderRadius: radii.inputShape,
      borderSide: BorderSide(color: borders.focus, width: 1.5),
    );
    final errorInputBorder = OutlineInputBorder(
      borderRadius: radii.inputShape,
      borderSide: BorderSide(color: borders.error),
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      textTheme: text,
      extensions: [isLight ? PawsTokens.light : PawsTokens.dark],
      splashFactory: InkRipple.splashFactory,
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
        },
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: text.titleMedium,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: Size(heights.button, heights.button),
          padding: EdgeInsets.symmetric(horizontal: spacing.xl),
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          textStyle: text.titleLarge?.copyWith(color: scheme.onPrimary),
          shape: buttonShape,
          elevation: 0,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: Size(heights.button, heights.button),
          padding: EdgeInsets.symmetric(horizontal: spacing.xl),
          foregroundColor: scheme.onSurface,
          textStyle: text.titleLarge?.copyWith(fontWeight: FontWeight.w500),
          side: BorderSide(color: borders.subtle),
          shape: buttonShape,
          backgroundColor: surfaces.card,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: scheme.onSurfaceVariant,
          textStyle: text.bodyLarge?.copyWith(fontWeight: FontWeight.w500),
          minimumSize: Size(heights.standard, heights.standard),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaces.input,
        contentPadding: EdgeInsets.symmetric(
          horizontal: spacing.inputHorizontal,
          vertical: spacing.inputVertical,
        ),
        hintStyle: text.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
        labelStyle: text.bodyMedium,
        border: inputBorder,
        enabledBorder: inputBorder,
        focusedBorder: focusedInputBorder,
        errorBorder: errorInputBorder,
        focusedErrorBorder: errorInputBorder.copyWith(
          borderSide: BorderSide(color: borders.error, width: 1.5),
        ),
        disabledBorder: inputBorder.copyWith(
          borderSide: BorderSide(color: states.disabledContent),
        ),
        errorStyle: text.bodySmall?.copyWith(color: states.error),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: surfaces.input,
        disabledColor: states.disabled,
        selectedColor: states.selected,
        padding: EdgeInsets.symmetric(
          horizontal: spacing.md,
          vertical: spacing.xs,
        ),
        labelStyle: text.titleSmall,
        secondaryLabelStyle: text.titleSmall,
        shape: RoundedRectangleBorder(borderRadius: radii.chipShape),
        side: BorderSide(color: borders.subtle),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surfaces.card,
        modalBackgroundColor: surfaces.card,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: radii.sheetShape),
        showDragHandle: true,
        dragHandleColor: borders.subtle,
        dragHandleSize: Size(36, spacing.xs),
      ),
      dividerTheme: DividerThemeData(
        color: borders.subtle,
        thickness: 1,
        space: 1,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: scheme.inverseSurface,
        contentTextStyle: text.bodyMedium?.copyWith(
          color: scheme.onInverseSurface,
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStatePropertyAll(surfaces.elevated),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return scheme.primary;
          return borders.standard;
        }),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
    );
  }
}
