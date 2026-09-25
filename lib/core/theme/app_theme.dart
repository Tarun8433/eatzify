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
    tint: AppColors.lightTint,
    onTint: AppColors.lightOnTint,
    warmTint: AppColors.lightTintWarm,
    onWarmTint: AppColors.lightOnTintWarm,
  );

  static ThemeData get dark => _build(
    brightness: Brightness.dark,
    background: AppColors.darkBackground,
    surface: AppColors.darkSurface,
    surfaceAlt: AppColors.darkSurfaceAlt,
    onSurface: AppColors.darkOnSurface,
    muted: AppColors.darkMuted,
    outline: AppColors.darkOutline,
    tint: AppColors.darkTint,
    onTint: AppColors.darkOnTint,
    warmTint: AppColors.darkTintWarm,
    onWarmTint: AppColors.darkOnTintWarm,
  );

  static ThemeData _build({
    required Brightness brightness,
    required Color background,
    required Color surface,
    required Color surfaceAlt,
    required Color onSurface,
    required Color muted,
    required Color outline,
    required Color tint,
    required Color onTint,
    required Color warmTint,
    required Color onWarmTint,
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
      // The icon tint, carried on the scheme rather than reached for from `AppColors` in a widget
      // (rule 5). `secondaryContainer` is Material's own "quiet tinted surface" role, which is
      // exactly what this is — and it leaves `surfaceContainerHighest` free to stay the warm beige
      // the progress track and the selected chip are built on.
      secondaryContainer: tint,
      onSecondaryContainer: onTint,
      // The warm counterpart: the streak reads as encouragement, not as another data card.
      tertiaryContainer: warmTint,
      onTertiaryContainer: onWarmTint,
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
      // The reference's `+` is the brand green, not the teal accent; dark mode keeps the accent
      // because deep green vanishes on a near-black page.
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: interactive,
        foregroundColor: isDark ? AppColors.darkBackground : Colors.white,
        shape: const CircleBorder(),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.sheet)),
        ),
      ),
      // The `+` sheet's four tabs (D-122). The active one is LIT — a tinted pill behind it — and
      // still underlined: a tint alone is a colour difference, and rule 12 does not accept colour
      // as the only signal. Set here rather than on the one TabBar so a second one cannot differ.
      tabBarTheme: TabBarThemeData(
        indicatorSize: TabBarIndicatorSize.tab,
        indicator: BoxDecoration(
          color: interactive.withValues(alpha: isDark ? 0.22 : 0.10),
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border(bottom: BorderSide(color: interactive, width: 2)),
        ),
        labelColor: interactive,
        unselectedLabelColor: muted,
        labelStyle: AppTextStyles.caption.copyWith(fontWeight: FontWeight.w700),
        unselectedLabelStyle: AppTextStyles.caption,
        dividerColor: outline,
      ),
      dividerTheme: DividerThemeData(color: outline, thickness: 1, space: 1),
      // D-106. Every field in the app is a rounded, filled card rather than a 4 pt-cornered
      // outline — set here rather than per-field so onboarding, the edit sheets and the log sheets
      // cannot drift apart. The radius is the tile radius the options already use: a question and
      // its answer should not have different corners.
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        // Roomy enough that a field is a card and not a line. The 48 dp touch target (rule 12)
        // comes from this, not from a fixed height, so it still grows with the text scale.
        // The LEFT inset is only ever used by a field with no leading disc — `InputDecorator`
        // drops it when a prefix is present, and `FieldIcon` owns the gaps around the disc there.
        // The right one is the gap before the picker button, and is tighter because half a phone
        // shared with a 48 dp button has no spare width to give it.
        contentPadding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.lg,
          AppSpacing.sm,
          AppSpacing.lg,
        ),
        // The leading disc is DECORATION, so it is not held to the 48 dp interactive minimum
        // Material applies to both affixes by default. The suffix is a real button and keeps it.
        // Those 8 pt are what let "Height (cm)" fit beside a picker button in half a phone.
        prefixIconConstraints: const BoxConstraints(
          minWidth: AppSpacing.xxl + AppSpacing.lg,
          minHeight: AppSpacing.xxl + AppSpacing.lg,
        ),
        // Half-strength (D-107). At full weight the warm outline was the loudest thing on the
        // screen and every field read as a box drawn around nothing; the reference separates a
        // field from the page with its shape and fill and leaves the line almost out of it.
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.tile),
          borderSide: BorderSide(color: outline.withValues(alpha: 0.5)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.tile),
          borderSide: BorderSide(color: outline.withValues(alpha: 0.5)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.tile),
          borderSide: BorderSide(color: interactive, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.tile),
          borderSide: const BorderSide(color: AppColors.danger),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.tile),
          borderSide: const BorderSide(color: AppColors.danger, width: 1.5),
        ),
        // Sits under the field rather than floating in it: the mock keeps "What should we call
        // you?" visible while the answer is typed, which a floating label cannot do.
        helperStyle: AppTextStyles.caption.copyWith(color: muted),
        hintStyle: AppTextStyles.label.copyWith(color: muted, fontWeight: FontWeight.w400),
        labelStyle: AppTextStyles.label.copyWith(color: muted, fontWeight: FontWeight.w400),
        floatingLabelStyle: AppTextStyles.label.copyWith(color: interactive),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          // Taller and rounder than a card (D-107). This is the only button on most screens and
          // the reference gives it real presence; `minTouchTarget` is the floor for a control, not
          // the size of the one thing the screen is asking you to press.
          minimumSize: const Size(0, AppSizes.primaryButton),
          textStyle: AppTextStyles.h2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.cardLarge)),
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
