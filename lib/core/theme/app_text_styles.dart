import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Six type roles, one family. docs/14 §5. No ad-hoc sizes anywhere else.
///
/// **One ratio, everywhere: 1.2 from a 15 pt body** (D-111). The sizes used to be picked one at a
/// time — 32 / 24 / 18 / 15 / 13 / 12, which steps by 1.33, 1.33, 1.20, 1.15, 1.08 — so the top of
/// the scale pulled away from the rest and a headline read as a different design from the sentence
/// under it. On a modular scale each role is one step from its neighbour, which is what makes a
/// screen look proportioned rather than merely large.
///
/// ```text
/// caption  12   floor
/// label    13   body / 1.2
/// body     15   the anchor
/// h2       18   body x 1.2
/// h1       22   body x 1.2^2
/// display  26   body x 1.2^3
/// ```
///
/// [caption] is held at 12 rather than continuing the scale to 10.4: it is the smallest text in
/// the app and the accessibility floor wins over the arithmetic. That one flat step is deliberate.
///
/// Sizes are in logical pixels and scale with the OS text setting — the app must survive 200 %
/// (CLAUDE.md rule 12), so never wrap these in a fixed-height box.
abstract final class AppTextStyles {
  /// Inter, the grotesque of the current Home reference mock (supersedes D-119's Montserrat,
  /// which matched the older `lib/screen` build this app grew out of).
  ///
  /// Served by `google_fonts`, which fetches once and caches. See `AppTheme` for the trade-off:
  /// bundling the four weights as assets is ~400 KB and removes the first-launch fetch entirely,
  /// and is worth doing before release in a market where a cold start can be offline.
  static TextStyle _font(TextStyle base) => GoogleFonts.inter(textStyle: base);

  static TextStyle get display =>
      _font(const TextStyle(fontSize: 26, fontWeight: FontWeight.w700, height: 1.2));
  static TextStyle get h1 =>
      _font(const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, height: 1.25));
  static TextStyle get h2 =>
      _font(const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, height: 1.3));
  static TextStyle get body =>
      _font(const TextStyle(fontSize: 15, fontWeight: FontWeight.w400, height: 1.45));
  static TextStyle get label =>
      _font(const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, height: 1.3));
  static TextStyle get caption =>
      _font(const TextStyle(fontSize: 12, fontWeight: FontWeight.w400, height: 1.35));
}
