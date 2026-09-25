import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:health_pro/core/format/phone_e164.dart';
import 'package:health_pro/core/theme/app_colors.dart';
import 'package:health_pro/core/theme/app_spacing.dart';
import 'package:health_pro/core/widgets/app_card.dart';
import 'package:health_pro/core/widgets/progress_ring.dart';
import 'package:health_pro/domain/entities/sent_invite.dart';
import 'package:health_pro/presentation/l10n/app_localizations.dart';

/// The pieces the coach dashboard is built from (D-200).
///
/// Kept in one file because they are one design: four tiles, a task column, a badge and a trend
/// line that all share the same tinted-glyph vocabulary. Split across five files they would drift.

/// A headline figure with its own tint, and what it did since last period.
///
/// The tint identifies the METRIC, never judges it — the same rule the macro rings follow. There is
/// no red tile for a bad number, because a coach's client count is not a grade.
class CoachStatTile extends StatelessWidget {
  const CoachStatTile({
    required this.icon,
    required this.tint,
    required this.value,
    required this.label,
    super.key,
    this.trendPct,
    this.trendCaption,
    this.onTap,
  });

  final IconData icon;
  final Color tint;
  final String value;
  final String label;

  /// Null draws no trend line at all. A first month has nothing to compare against, and "0 %" would
  /// claim it was flat.
  final int? trendPct;
  final String? trendCaption;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SizedBox(
      width: AppSizes.coachTile,
      child: AppCard(
        padding: const EdgeInsets.all(AppSpacing.md),
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            ExcludeSemantics(
              child: Container(
                height: AppSizes.choiceDisc,
                width: AppSizes.choiceDisc,
                decoration: BoxDecoration(
                  color: tint.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppRadius.card),
                ),
                child: Icon(icon, size: AppSpacing.lg, color: tint),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            Text(
              label,
              maxLines: 2,
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            if (trendPct case final pct?) ...[
              const SizedBox(height: AppSpacing.xs),
              TrendLine(pct: pct, caption: trendCaption),
            ],
          ],
        ),
      ),
    );
  }
}

/// "↑ 12 % vs last 30 days".
///
/// **Caption ink, never green or red.** docs/05 §6 keeps a direction from carrying a verdict, and
/// this row sits above client numbers where a green arrow would read as a score.
class TrendLine extends StatelessWidget {
  const TrendLine({required this.pct, super.key, this.caption});

  final int pct;
  final String? caption;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          pct < 0 ? Icons.arrow_downward : Icons.arrow_upward,
          size: AppSpacing.md,
          color: theme.colorScheme.onSurfaceVariant,
        ),
        Flexible(
          child: Text(
            caption == null ? '${pct.abs()}%' : '${pct.abs()}%  $caption',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: muted,
          ),
        ),
      ],
    );
  }
}

/// One of the three things a coach might do today: a count, a label, somewhere to go.
class CoachTask extends StatelessWidget {
  const CoachTask({
    required this.icon,
    required this.tint,
    required this.count,
    required this.label,
    super.key,
    this.onTap,
  });

  final IconData icon;
  final Color tint;
  final int count;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
          child: Column(
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  ExcludeSemantics(
                    child: Container(
                      height: AppSizes.ringSmall,
                      width: AppSizes.ringSmall,
                      decoration: BoxDecoration(
                        color: tint.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(icon, color: tint),
                    ),
                  ),
                  // Absent at zero rather than a badge reading "0". Nothing to do is not a task.
                  if (count > 0)
                    Positioned(
                      right: -AppSpacing.xs,
                      top: -AppSpacing.xs,
                      child: _CountBadge(count: count),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 2,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs, vertical: 1),
      constraints: const BoxConstraints(minWidth: AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.warmCoral,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(
        '$count',
        textAlign: TextAlign.center,
        style: theme.textTheme.labelSmall?.copyWith(
          color: Colors.white,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// A small tinted label. Used for a subscription tier and for how recently somebody logged.
class BadgePill extends StatelessWidget {
  const BadgePill({required this.label, required this.tint, super.key});

  final String label;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 2),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(color: tint, fontWeight: FontWeight.w700),
      ),
    );
  }
}

/// The adherence ring on a client row.
///
/// Absent, not zero, when the client has never logged: docs/02 FR-4.2 asks for "a count not a shame
/// badge", and an empty ring reading 0 % is the badge.
class AdherenceRing extends StatelessWidget {
  const AdherenceRing({required this.pct, super.key});

  final int? pct;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final value = pct;

    return ProgressRing(
      size: AppSizes.ringSmall,
      strokeWidth: 5,
      progress: value == null ? null : value / 100,
      child: Text(
        value == null ? '—' : '$value%',
        style: theme.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w700),
      ),
    );
  }
}

/// docs/12 §9's three states, through l10n (rule 4) and with the wording docs/05 §6 requires — a
/// long absence is a fact about the diary, never a verdict on the person.
String coachStatusLabel(AppLocalizations l, String? status) => switch (status) {
  'active' => l.coachStatusActive,
  'at_risk' => l.coachStatusAtRisk,
  _ => l.coachStatusNoRecentLogs,
};

Color coachStatusTint(String? status) => switch (status) {
  'active' => AppColors.success,
  'at_risk' => AppColors.warning,
  _ => AppColors.macroFat,
};

String coachTierLabel(AppLocalizations l, String? tier) => switch (tier) {
  'PRO' => l.coachTierPro,
  'BASIC' => l.coachTierBasic,
  _ => l.coachTierFree,
};

/// Invites were stored with whatever the coach typed until the number was normalised, so the same
/// human can hold two pending rows — `8433145573` and `+918433145573` were both on this screen,
/// looking like two people. Grouping on the digits keeps the newest ask and hides the duplicate.
List<SentInvite> oneRowPerPerson(List<SentInvite> rows) {
  final byPerson = <String, SentInvite>{};

  for (final invite in rows) {
    // The last ten digits, not all of them: `8433145573` and `+918433145573` are the same person,
    // and keying on every digit would keep the country code and split them again.
    final digits = invite.phoneE164.replaceAll(RegExp(r'[^0-9]'), '');
    final key = digits.length <= 10 ? digits : digits.substring(digits.length - 10);
    final held = byPerson[key];
    final newer =
        held == null || (invite.createdAt?.isAfter(held.createdAt ?? DateTime(0)) ?? false);
    if (newer) byPerson[key] = invite;
  }

  return byPerson.values.toList();
}

/// Somebody who has been asked and has not answered.
///
/// Named when the number belongs to an account, shown as the number when it does not. A made-up
/// name would be a claim about somebody who may not be here at all.
class InvitedCard extends StatelessWidget {
  const InvitedCard({required this.invite, super.key});

  final SentInvite invite;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final name = invite.name;

    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        children: [
          ExcludeSemantics(
            child: CircleAvatar(
              radius: AppSpacing.xl,
              backgroundColor: scheme.surfaceContainerHighest,
              child: Icon(Icons.hourglass_empty, color: scheme.onSurfaceVariant),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  // The number as a person reads it, not as it is stored. `+918433145573` is the
                  // same number nobody recognises.
                  name ?? PhoneE164.display(invite.phoneE164),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
                Text(
                  name == null ? l.coachInviteNotOnApp : PhoneE164.display(invite.phoneE164),
                  style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                ),
                // When an ask runs out. A coach who cannot see this has no way to know whether
                // to send it again — docs/09 §6 gives an invite 30 days.
                if (invite.expiresAt case final expires?)
                  Text(
                    l.coachInviteExpires(DateFormat.yMMMd().format(expires)),
                    style: theme.textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
