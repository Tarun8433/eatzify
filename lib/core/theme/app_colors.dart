import 'package:flutter/material.dart';

/// Colour tokens. docs/14 §5. Nothing in the app may use a raw `Color(0x…)`.
abstract final class AppColors {
  // Brand
  static const primary = Color(0xFF0B3B2E);
  static const accent = Color(0xFF12A67F);

  // Semantic — note there is deliberately no "failure" red for user progress.
  // docs/05 §6: never mark a past day red as missed. Danger is for destructive actions only.
  static const success = Color(0xFF2E7D5B);
  static const warning = Color(0xFFB26A00);
  static const danger = Color(0xFFB3261E);
  static const info = Color(0xFF1B6C9C);

  // Light surfaces
  static const lightBackground = Color(0xFFF7F9F8);
  static const lightSurface = Color(0xFFFFFFFF);
  static const lightSurfaceAlt = Color(0xFFEDF2F0);
  static const lightOnSurface = Color(0xFF12211C);
  static const lightMuted = Color(0xFF5C6B65);
  static const lightOutline = Color(0xFFD3DEDA);

  // Dark surfaces
  static const darkBackground = Color(0xFF0D1512);
  static const darkSurface = Color(0xFF14201C);
  static const darkSurfaceAlt = Color(0xFF1D2C27);
  static const darkOnSurface = Color(0xFFE6EDEA);
  static const darkMuted = Color(0xFF9BAAA4);
  static const darkOutline = Color(0xFF2C3B36);
}
