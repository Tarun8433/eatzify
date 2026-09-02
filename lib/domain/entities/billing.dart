/// What the server says this account may use. docs/11 §4: entitlements are resolved SERVER-side —
/// the app renders them and never computes one (CLAUDE.md rule 3).
class Entitlements {
  const Entitlements({required this.tier, required this.status});

  Entitlements.fromJson(Map<String, dynamic> json)
    : this(
        tier: json['tier']?.toString() ?? 'FREE',
        status: json['status']?.toString() ?? 'active',
      );

  /// FREE / BASIC / PRO — the server's vocabulary, shown through l10n (rule 4).
  final String tier;
  final String status;

  /// The one question the UI asks: is there anything to sell this person? A paid tier, in any
  /// status the server still honours, means the upgrade surfaces stay away (docs/11 §10 names
  /// "upgrade CTA while subscribed" as a shipped defect of the old build).
  bool get isFree => tier == 'FREE';
}

/// One purchasable cell of the price matrix: a tier for a duration, in paise (rule: money is
/// integer paise, never rupees-as-decimal).
class TierPrice {
  const TierPrice({required this.tier, required this.months, required this.pricePaise});

  final String tier;
  final int months;
  final int pricePaise;
}
