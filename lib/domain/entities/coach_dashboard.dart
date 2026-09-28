import 'package:health_pro/domain/entities/coach_client.dart';

/// `GET /coach/dashboard` (D-200). What a trainer, nutritionist or doctor opens their day on.
///
/// The counts and [needsAttention] are built from the same rows on the server, so a number on a
/// tile can never disagree with the list under it.
class CoachDashboard {
  const CoachDashboard({
    required this.totalClients,
    required this.activeClients,
    required this.atRiskClients,
    required this.pendingInvites,
    required this.renewalsDue30d,
    required this.needsAttention,
  });

  CoachDashboard.fromJson(Map<String, dynamic> json)
    : this(
        totalClients: (json['total_clients'] as num?)?.toInt() ?? 0,
        activeClients: (json['active_clients'] as num?)?.toInt() ?? 0,
        atRiskClients: (json['at_risk_clients'] as num?)?.toInt() ?? 0,
        pendingInvites: (json['pending_invites'] as num?)?.toInt() ?? 0,
        renewalsDue30d: (json['renewals_due_30d'] as num?)?.toInt() ?? 0,
        needsAttention:
            (json['needs_attention'] as List?)
                ?.map((r) => CoachClient.fromJson(r as Map<String, dynamic>))
                .toList() ??
            const [],
      );

  final int totalClients;
  final int activeClients;
  final int atRiskClients;
  final int pendingInvites;
  final int renewalsDue30d;

  /// docs/12 §9 calls this "the single most valuable widget you can give a coach". Longest since a
  /// log first — never sorted by weight lost or streak, which would be the leaderboard docs/05 §6
  /// bans.
  final List<CoachClient> needsAttention;

  /// Nothing to show and nothing to chase. A brand-new partner, which is ordinary rather than
  /// broken.
  bool get isEmpty => totalClients == 0 && pendingInvites == 0;
}

/// `GET /coach/earnings?period=` (D-201). Aggregate only — docs/12 §8 keeps a per-client line out,
/// because it would tell an affiliate exactly what one person paid.
class CoachEarnings {
  const CoachEarnings({
    required this.period,
    required this.totalPaise,
    required this.clientPaymentsPaise,
    required this.bonusPaise,
    required this.otherPaise,
    required this.daily,
    this.pctChange,
  });

  CoachEarnings.fromJson(Map<String, dynamic> json)
    : this(
        period: json['period']?.toString() ?? '',
        totalPaise: _paise(json['total_paise']),
        clientPaymentsPaise: _paise((json['breakdown'] as Map?)?['client_payments_paise']),
        bonusPaise: _paise((json['breakdown'] as Map?)?['bonus_paise']),
        otherPaise: _paise((json['breakdown'] as Map?)?['other_paise']),
        daily:
            (json['sparkline'] as List?)
                ?.map((p) => _paise((p as Map)['paise']).toDouble())
                .toList() ??
            const [],
        pctChange: (json['pct_change'] as num?)?.toInt(),
      );

  /// `YYYY-MM`.
  final String period;

  /// Integer paise on the wire and here. Rupees happen once, at the edge of the widget that prints
  /// them — the same rule the price matrix follows.
  final int totalPaise;
  final int clientPaymentsPaise;
  final int bonusPaise;

  /// Reversals land here, so a month that went down shows why rather than simply being smaller.
  final int otherPaise;

  /// One point per day of the month, already zero-filled by the server. A quiet week is a flat
  /// line, not a gap.
  final List<double> daily;

  /// Null, never zero, when there is no previous month to compare against. A first month is not a
  /// flat month.
  final int? pctChange;

  bool get isEmpty => totalPaise == 0 && daily.every((p) => p == 0);
}

/// `GET /coach/referral`. The code a partner shares and the link that carries it.
class CoachReferral {
  const CoachReferral({required this.code, required this.url});

  CoachReferral.fromJson(Map<String, dynamic> json)
    : this(code: json['code']?.toString() ?? '', url: json['url']?.toString() ?? '');

  final String code;
  final String url;
}

/// Money arrives as a string because it is a BIGINT — `api/CLAUDE.md` rule 3 keeps paise out of
/// float territory, and JSON numbers are doubles.
int _paise(Object? raw) => int.tryParse(raw?.toString() ?? '') ?? 0;
