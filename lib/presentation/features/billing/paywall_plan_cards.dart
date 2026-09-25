import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:health_pro/core/format/rupees.dart';
import 'package:health_pro/core/theme/app_spacing.dart';
import 'package:health_pro/domain/entities/billing.dart';
import 'package:health_pro/presentation/features/billing/billing_controller.dart';
import 'package:health_pro/presentation/features/billing/tier_palette.dart';
import 'package:health_pro/presentation/l10n/app_localizations.dart';

/// The tiers as cards, one per tier the server priced, each holding that tier's durations.
///
/// Side by side while both cards clear [AppSizes.tierCardMin], stacked below it. The threshold is
/// measured against the SCALED width, so a 200 % text scale stacks them on the same phone that
/// shows them side by side at 100 % (rule 12) — one rule rather than a width breakpoint and a text
/// breakpoint that can disagree.
class TierPlanCards extends StatelessWidget {
  const TierPlanCards({required this.billing, super.key});

  final BillingController billing;

  @override
  Widget build(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context).scale(AppSizes.tierCardMin);

    return Obx(() {
      final tiers = billing.tiers;
      if (tiers.isEmpty) return const SizedBox.shrink();

      return LayoutBuilder(
        builder: (context, constraints) {
          final each = (constraints.maxWidth - AppSpacing.md * (tiers.length - 1)) / tiers.length;
          final cards = [for (final tier in tiers) _TierCard(billing: billing, tier: tier)];

          if (each < scale) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final card in cards) ...[
                  card,
                  if (card != cards.last) const SizedBox(height: AppSpacing.md),
                ],
              ],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final card in cards) ...[
                Expanded(child: card),
                if (card != cards.last) const SizedBox(width: AppSpacing.md),
              ],
            ],
          );
        },
      );
    });
  }
}

class _TierCard extends StatelessWidget {
  const _TierCard({required this.billing, required this.tier});

  final BillingController billing;
  final String tier;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final style = tierStyleFor(tier, theme.brightness);
    final tagline = tierTagline(l, tier);

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: style.tint,
        borderRadius: BorderRadius.circular(AppRadius.cardLarge),
        border: Border.all(color: style.ink.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Above the name rather than beside it. Sharing the row cost the tier's name every point
          // the badge took, and two cards on a 393 pt phone have about 150 pt each to give.
          //
          // The unbadged card keeps the SPACE, so both cards start their prices on the same line —
          // two ladders offset by the height of a pill are two ladders that cannot be compared by
          // running an eye across them. `maintainSemantics` stays false, so nothing announces a
          // badge that is not there.
          Align(
            alignment: Alignment.centerRight,
            child: Visibility(
              visible: isPopularTier(tier),
              maintainSize: true,
              maintainAnimation: true,
              maintainState: true,
              child: _PopularBadge(style: style),
            ),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // The mark is decoration; the tier's NAME beside it carries the meaning.
              ExcludeSemantics(
                child: Container(
                  height: AppSizes.ringSmall,
                  width: AppSizes.ringSmall,
                  decoration: BoxDecoration(color: style.badge, shape: BoxShape.circle),
                  child: Icon(style.icon, color: style.ink, size: AppSpacing.xl),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tierLabel(l, tier),
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: style.ink,
                      ),
                    ),
                    if (tagline != null)
                      Text(tagline, style: theme.textTheme.bodySmall?.copyWith(color: style.ink)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          for (final price in billing.pricesFor(tier))
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: _DurationRow(billing: billing, price: price, style: style),
            ),
        ],
      ),
    );
  }
}

class _PopularBadge extends StatelessWidget {
  const _PopularBadge({required this.style});

  final TierStyle style;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
      decoration: BoxDecoration(
        color: style.badge,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(
        l.premiumMostPopular,
        style: theme.textTheme.labelSmall?.copyWith(color: style.ink, fontWeight: FontWeight.w700),
      ),
    );
  }
}

/// One duration inside a tier card. The whole row is the target — a 20 pt radio is not a 48 dp
/// touch target, and asking someone to hit the circle rather than the price they are reading is
/// the kind of thing rule 12 exists to stop.
class _DurationRow extends StatelessWidget {
  const _DurationRow({required this.billing, required this.price, required this.style});

  final BillingController billing;
  final TierPrice price;
  final TierStyle style;

  /// Rupees per month, or per year, ROUNDED — `1,199 / 6` is ₹199.83 and reads as ₹200 on every
  /// pricing page there has ever been. Integer division would print ₹199 and quietly understate
  /// the longer terms by a rupee each.
  String _perPeriod(AppLocalizations l) {
    final months = price.months;
    if (billing.perYear.value) {
      final perYear = (price.pricePaise * 12 / (months * 100)).round();
      return l.premiumPerYear(Rupees.format(perYear));
    }
    final perMonth = (price.pricePaise / (months * 100)).round();
    return l.premiumPerMonth(Rupees.format(perMonth));
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Obx(() {
      final selected = billing.isSelected(price.tier, price.months);
      final term = l.premiumMonths(price.months);
      final total = Rupees.format(price.pricePaise ~/ 100);

      return Semantics(
        inMutuallyExclusiveGroup: true,
        selected: selected,
        label: '${tierLabel(l, price.tier)} · $term · $total',
        excludeSemantics: true,
        child: Material(
          color: selected ? style.badge : theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(AppRadius.card),
          child: InkWell(
            onTap: () => billing.select(price.tier, price.months),
            borderRadius: BorderRadius.circular(AppRadius.card),
            child: Container(
              constraints: const BoxConstraints(minHeight: AppSpacing.minTouchTarget),
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.xs,
                vertical: AppSpacing.xs,
              ),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppRadius.card),
                // Selection is a ring AND a fill, never colour alone (rule 12).
                border: Border.all(
                  color: selected ? style.ink : theme.colorScheme.outline,
                  width: selected ? 2 : 1,
                ),
              ),
              child: Row(
                children: [
                  _RadioDot(selected: selected, ink: style.ink),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Text(
                      term,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        total,
                        style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        _perPeriod(l),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    });
  }
}

/// Drawn rather than a [Radio], so the ring takes the tier's ink instead of the one global
/// interactive colour — two cards whose selected states are the same green is the thing the warm
/// pair exists to prevent.
class _RadioDot extends StatelessWidget {
  const _RadioDot({required this.selected, required this.ink});

  final bool selected;
  final Color ink;

  @override
  Widget build(BuildContext context) {
    final outline = Theme.of(context).colorScheme.outline;

    return Container(
      height: AppSpacing.lg,
      width: AppSpacing.lg,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: selected ? ink : outline, width: 2),
      ),
      child: selected
          ? Center(
              child: Container(
                height: AppSpacing.sm,
                width: AppSpacing.sm,
                decoration: BoxDecoration(color: ink, shape: BoxShape.circle),
              ),
            )
          : null,
    );
  }
}
