import 'package:flutter/material.dart';

/// Six type roles, one family. docs/14 §5. No ad-hoc sizes anywhere else.
///
/// Sizes are in logical pixels and scale with the OS text setting — the app must survive 200 %
/// (CLAUDE.md rule 12), so never wrap these in a fixed-height box.
abstract final class AppTextStyles {
  static const _family = 'Roboto';

  static const display = TextStyle(
    fontFamily: _family,
    fontSize: 32,
    fontWeight: FontWeight.w700,
    height: 1.2,
  );
  static const h1 = TextStyle(
    fontFamily: _family,
    fontSize: 24,
    fontWeight: FontWeight.w700,
    height: 1.25,
  );
  static const h2 = TextStyle(
    fontFamily: _family,
    fontSize: 18,
    fontWeight: FontWeight.w600,
    height: 1.3,
  );
  static const body = TextStyle(
    fontFamily: _family,
    fontSize: 15,
    fontWeight: FontWeight.w400,
    height: 1.45,
  );
  static const label = TextStyle(
    fontFamily: _family,
    fontSize: 13,
    fontWeight: FontWeight.w600,
    height: 1.3,
  );
  static const caption = TextStyle(
    fontFamily: _family,
    fontSize: 12,
    fontWeight: FontWeight.w400,
    height: 1.35,
  );
}
