import 'package:flutter/material.dart';

/// Colour tokens. docs/14 §5. Nothing in the app may use a raw `Color(0x…)`.
abstract final class AppColors {
  // Brand
  static const primary = Color(0xFF0B3B2E);

  /// The darker end of the calorie card's gradient — the reference mock's green card is lit from
  /// the top-left, not flat. Only ever paired with [primary]; never a surface on its own.
  static const primaryDeep = Color(0xFF062219);

  static const accent = Color(0xFF12A67F);

  /// Emphasis on dark surfaces only — the big number on a stat tile, an active tab.
  /// 10.2:1 on darkBackground against `accent`'s 6.0:1, so a headline figure stays legible at the
  /// small sizes a stat tile uses. Never used on a light surface, where it fails contrast.
  static const accentBright = Color(0xFF1FD9A4);

  /// The three macros, outer to inner on the rings and top to bottom on the goal tiles (D-61).
  /// The reference's exact hues and saturation, darkened only as far as white text needs: each
  /// clears 4.5:1 on white (4.6, 6.0, 4.6), so the same token serves the ring and the tile it
  /// labels. They are identity, never judgement — a macro keeps its colour whether under target or
  /// over, which is what docs/05 §6 actually forbids changing.
  static const macroProtein = Color(0xFFCD480B);
  static const macroCarb = Color(0xFF6C33FC);
  static const macroFat = Color(0xFF017DB0);

  /// The warm dot on the welcome medallion. The only place a colour is used purely as warmth —
  /// a coral heart against the greens, so the first screen is not monochrome. Never used behind
  /// text: it is decoration, and nothing reads on it.
  static const warmCoral = Color(0xFFE8825E);

  // Semantic — note there is deliberately no "failure" red for user progress.
  // docs/05 §6: never mark a past day red as missed. Danger is for destructive actions only.
  static const success = Color(0xFF2E7D5B);
  static const warning = Color(0xFFB26A00);
  static const danger = Color(0xFFB3261E);
  static const info = Color(0xFF1B6C9C);

  // Light surfaces
  // The near-white page of the current Home reference mock — barely warm, so the green cards and
  // the walker carry the colour and the page stays out of it. (Replaces D-58's cream, which read
  // peach next to the mock.) Lighter than the old value, so every text ratio only improves.
  static const lightBackground = Color(0xFFF7F6F2);
  static const lightSurface = Color(0xFFFFFFFF);
  static const lightSurfaceAlt = Color(0xFFF3E6DD);
  static const lightOnSurface = Color(0xFF12211C);
  static const lightMuted = Color(0xFF5C6B65);
  // A white card is 1.08:1 against this page, so the edge does the separating, not the fill — which
  // is why this is warmer AND stronger than the green it replaced (1.94:1 on white, was 1.75:1).
  static const lightOutline = Color(0xFFC6B8A9);

  /// The tint behind an icon: the disc on an option row, the disc in a field, the hint card
  /// (D-107). A GREEN wash, not `lightSurfaceAlt` — the beige read as a smudge of the page rather
  /// than as part of the brand, and it is the single thing that made the build look unlike the
  /// reference at a glance. Deliberately desaturated: forty of these are on screen at once during
  /// onboarding, and a saturated one would compete with the answer beside it.
  /// `lightOnTint` is 6.6:1 on it, and 8.0:1 on white where the hint card puts it.
  static const lightTint = Color(0xFFE3EDD4);
  static const lightOnTint = Color(0xFF2C5A34);

  // Dark surfaces
  static const darkBackground = Color(0xFF0D1512);
  static const darkSurface = Color(0xFF14201C);
  static const darkSurfaceAlt = Color(0xFF1D2C27);
  static const darkOnSurface = Color(0xFFE6EDEA);
  static const darkMuted = Color(0xFF9BAAA4);
  static const darkOutline = Color(0xFF2C3B36);

  /// The dark-mode tint (D-107). A lifted surface with a green cast rather than a pale wash —
  /// `lightTint` on a near-black page is a glare, and the disc has to read as a recess.
  /// `darkOnTint` is 8.1:1 on it.
  static const darkTint = Color(0xFF223026);
  static const darkOnTint = Color(0xFFA8D0AE);

  /// The paywall's second tier (D-160). Premium is sold as two cards side by side, and two cards in
  /// the same green differ only by the words on them — the warm pair is what makes PRO read as the
  /// other choice at a glance rather than as a repeat of BASIC.
  ///
  /// Deliberately the same contrast as the green tint pair it sits beside (6.6:1 light, 8.8:1 dark
  /// against 6.6 and 8.1), so neither card is the harder one to read. [warning] is 3.8:1 on the
  /// light tint: it is the crown and the badge's edge — a UI boundary at WCAG 1.4.11's 3:1 — and
  /// never text, which takes `onTintWarm`.
  static const lightTintWarm = Color(0xFFFDF0D9);
  static const lightOnTintWarm = Color(0xFF7A4A00);
  static const darkTintWarm = Color(0xFF32271A);
  static const darkOnTintWarm = Color(0xFFE8C48A);

  /// The "most popular" pill, one step up from the card it sits on so the badge is a badge rather
  /// than a word floating on the same wash. 5.5:1 light and 6.6:1 dark with `onTintWarm` on it.
  static const lightBadgeWarm = Color(0xFFF7D9A8);
  static const darkBadgeWarm = Color(0xFF4A3A22);

  /// A border that carries meaning (a selected chip, a focused field) rather than decoration.
  /// WCAG 1.4.11 asks 3:1 for UI boundaries; `darkOutline` is 1.4:1 and is for decoration only.
  static const darkOutlineStrong = Color(0xFF5A6E67);
  static const lightOutlineStrong = Color(0xFF8B7D6E);
}
