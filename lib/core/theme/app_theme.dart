import 'package:flutter/material.dart';
import 'package:health_pro/core/theme/app_colors.dart';
import 'package:health_pro/core/theme/app_spacing.dart';
import 'package:health_pro/core/theme/app_text_styles.dart';

/// Light and dark themes. docs/14 §5: the settings screen advertises a theme switch, so dark mode
/// has to actually work — it is not decoration.
abstract final class AppTheme {
  static ThemeData get light => _build(
    brightness: Brightness.light,
    background: AppColors.lightBackground,
    surface: AppColors.lightSurface,
    surfaceAlt: AppColors.lightSurfaceAlt,
    onSurface: AppColors.lightOnSurface,
    muted: AppColors.lightMuted,
    outline: AppColors.lightOutline,
  );

  static ThemeData get dark => _build(
    brightness: Brightness.dark,
    background: AppColors.darkBackground,
    surface: AppColors.darkSurface,
    surfaceAlt: AppColors.darkSurfaceAlt,
    onSurface: AppColors.darkOnSurface,
    muted: AppColors.darkMuted,
    outline: AppColors.darkOutline,
  );

  static ThemeData _build({
    required Brightness brightness,
    required Color background,
    required Color surface,
    required Color surfaceAlt,
    required Color onSurface,
    required Color muted,
    required Color outline,
  }) {
    final isDark = brightness == Brightness.dark;
    // Accent carries the interactive role in dark mode — deep green lacks contrast on a dark ground.
    final interactive = isDark ? AppColors.accent : AppColors.primary;

    final scheme = ColorScheme(
      brightness: brightness,
      primary: interactive,
      onPrimary: isDark ? AppColors.darkBackground : Colors.white,
      secondary: AppColors.accent,
      onSecondary: isDark ? AppColors.darkBackground : Colors.white,
      error: AppColors.danger,
      onError: Colors.white,
      surface: surface,
      onSurface: onSurface,
      surfaceContainerHighest: surfaceAlt,
      outline: outline,
      outlineVariant: outline,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      textTheme: TextTheme(
        displayLarge: AppTextStyles.display.copyWith(color: onSurface),
        headlineMedium: AppTextStyles.h1.copyWith(color: onSurface),
        titleMedium: AppTextStyles.h2.copyWith(color: onSurface),
        bodyMedium: AppTextStyles.body.copyWith(color: onSurface),
        labelLarge: AppTextStyles.label.copyWith(color: onSurface),
        bodySmall: AppTextStyles.caption.copyWith(color: muted),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: background,
        foregroundColor: onSurface,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: AppTextStyles.h2.copyWith(color: onSurface),
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.card),
          side: BorderSide(color: outline),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surface,
        indicatorColor: interactive.withValues(alpha: isDark ? 0.24 : 0.12),
        elevation: 0,
        height: 68,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => AppTextStyles.caption.copyWith(
            color: states.contains(WidgetState.selected) ? interactive : muted,
            fontWeight: states.contains(WidgetState.selected) ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.accent,
        foregroundColor: Colors.white,
        shape: CircleBorder(),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.sheet)),
        ),
      ),
      dividerTheme: DividerThemeData(color: outline, thickness: 1, space: 1),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, AppSpacing.minTouchTarget),
          textStyle: AppTextStyles.label,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.card)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(0, AppSpacing.minTouchTarget),
          textStyle: AppTextStyles.label,
        ),
      ),
    );
  }
}
