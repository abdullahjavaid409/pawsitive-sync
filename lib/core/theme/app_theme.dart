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
      error: AppColors.error,
      onError: AppColors.white,
      errorContainer: AppColors.errorContainer,
      onErrorContainer: AppColors.onErrorContainer,
      surface: isLight ? AppColors.background : AppColors.darkSurface,
      onSurface: isLight ? AppColors.ink : AppColors.darkInk,
      onSurfaceVariant: isLight ? AppColors.muted : AppColors.darkMuted,
      outline: isLight ? AppColors.stroke : AppColors.darkStroke,
      outlineVariant: isLight ? AppColors.hairline : AppColors.darkHairline,
      shadow: AppColors.ink,
      scrim: AppColors.scrim,
      inverseSurface: isLight ? AppColors.ink : AppColors.background,
      onInverseSurface: isLight ? AppColors.background : AppColors.ink,
      inversePrimary: AppColors.brandSoft,
      surfaceTint: Colors.transparent,
      surfaceContainerLowest: isLight ? AppColors.white : AppColors.darkCard,
      surfaceContainerLow: isLight
          ? AppColors.background
          : AppColors.darkSurface,
      surfaceContainer: isLight ? AppColors.neutral : AppColors.darkNeutral,
      surfaceContainerHigh: isLight ? AppColors.divider : AppColors.darkDivider,
      surfaceContainerHighest: isLight
          ? AppColors.hairline
          : AppColors.darkHairline,
    );

    final base = isLight
        ? ThemeData.light().textTheme
        : ThemeData.dark().textTheme;
    final geist = base.apply(
      fontFamily: 'Geist',
      bodyColor: scheme.onSurface,
      displayColor: scheme.onSurface,
    );
    final text = geist.copyWith(
      displaySmall: geist.displaySmall?.copyWith(
        fontSize: 34,
        height: 1.08,
        fontWeight: FontWeight.w600,
        letterSpacing: -1.2,
        color: scheme.onSurface,
      ),
      headlineMedium: geist.headlineMedium?.copyWith(
        fontSize: 30,
        height: 1.12,
        fontWeight: FontWeight.w600,
        letterSpacing: -1.05,
        color: scheme.onSurface,
      ),
      headlineSmall: geist.headlineSmall?.copyWith(
        fontSize: 24,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.7,
        color: scheme.onSurface,
      ),
      titleLarge: geist.titleLarge?.copyWith(
        fontSize: 17,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.17,
        color: scheme.onSurface,
      ),
      titleMedium: geist.titleMedium?.copyWith(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.16,
        color: scheme.onSurface,
      ),
      titleSmall: geist.titleSmall?.copyWith(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        color: scheme.onSurface,
      ),
      bodyLarge: geist.bodyLarge?.copyWith(
        fontSize: 16,
        height: 1.45,
        fontWeight: FontWeight.w400,
        color: scheme.onSurface,
      ),
      bodyMedium: geist.bodyMedium?.copyWith(
        fontSize: 14,
        height: 1.4,
        fontWeight: FontWeight.w400,
        color: scheme.onSurfaceVariant,
      ),
      bodySmall: geist.bodySmall?.copyWith(
        fontSize: 13,
        fontWeight: FontWeight.w400,
        color: scheme.onSurfaceVariant,
      ),
      labelLarge: geist.labelLarge?.copyWith(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.1,
      ),
      labelSmall: geist.labelSmall?.copyWith(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.5,
        color: scheme.onSurfaceVariant,
      ),
    );

    final radius14 = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(14),
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
          minimumSize: const Size.fromHeight(56),
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          textStyle: text.titleLarge?.copyWith(color: scheme.onPrimary),
          shape: radius14,
          elevation: 0,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(56),
          foregroundColor: scheme.onSurface,
          textStyle: text.titleLarge?.copyWith(fontWeight: FontWeight.w500),
          side: BorderSide(color: scheme.outlineVariant),
          shape: radius14,
          backgroundColor: scheme.surfaceContainerLowest,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: scheme.onSurfaceVariant,
          textStyle: text.bodyLarge?.copyWith(fontWeight: FontWeight.w500),
          minimumSize: const Size.fromHeight(48),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerLowest,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        hintStyle: text.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
        labelStyle: text.bodyMedium,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: scheme.primary, width: 1.5),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant,
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
        thumbColor: const WidgetStatePropertyAll(AppColors.white),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return AppColors.brand;
          return isLight ? AppColors.stroke : AppColors.darkStroke;
        }),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
    );
  }
}
