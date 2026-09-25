import 'package:flutter/material.dart';
import 'package:health_pro/core/theme/app_colors.dart';
import 'package:health_pro/presentation/l10n/app_localizations.dart';

/// How one tier is drawn on the paywall: its wash, the ink that reads on it, and its mark.
///
/// A record rather than a colour per widget, because the two cards must differ in EVERY one of
/// these together — a green card with a crown, or an amber card with the green tint's ink, is how
/// two cards stop reading as two choices (D-160).
typedef TierStyle = ({Color tint, Color ink, Color badge, IconData icon});

/// The wire tier (`BASIC`, `PRO`) is never shown — CLAUDE.md rule 4. This maps it to paint;
/// [tierLabel] maps it to words.
TierStyle tierStyleFor(String tier, Brightness brightness) {
  final isDark = brightness == Brightness.dark;
  // PRO is the warm card. Anything the server prices that is not PRO takes the brand green, so a
  // tier added on the server renders as a plain card rather than as an unpainted one.
  if (tier == 'PRO') {
    return (
      tint: isDark ? AppColors.darkTintWarm : AppColors.lightTintWarm,
      ink: isDark ? AppColors.darkOnTintWarm : AppColors.lightOnTintWarm,
      badge: isDark ? AppColors.darkBadgeWarm : AppColors.lightBadgeWarm,
      icon: Icons.workspace_premium,
    );
  }
  return (
    tint: isDark ? AppColors.darkTint : AppColors.lightTint,
    ink: isDark ? AppColors.darkOnTint : AppColors.lightOnTint,
    badge: isDark ? AppColors.darkTint : AppColors.lightTint,
    icon: Icons.eco_outlined,
  );
}

/// CLAUDE.md rule 4: a tier is a wire value and l10n on screen.
String tierLabel(AppLocalizations l, String tier) => switch (tier) {
  'BASIC' => l.tierBasic,
  'PRO' => l.tierPro,
  // A tier the server starts selling before this app knows its name is shown as the server spells
  // it, which is ugly and honest — better than a card labelled with the wrong tier's name.
  _ => tier,
};

/// The line under a tier's name. Only the two tiers that exist have one; a new tier gets a card
/// without a tagline rather than another tier's promise.
String? tierTagline(AppLocalizations l, String tier) => switch (tier) {
  'BASIC' => l.premiumTierBasicTagline,
  'PRO' => l.premiumTierProTagline,
  _ => null,
};

/// Which card carries the badge. The server does not say what is popular, so this is presentation
/// and is deliberately one place rather than a flag threaded through the widgets.
bool isPopularTier(String tier) => tier == 'PRO';
