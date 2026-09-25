import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:health_pro/core/theme/app_colors.dart';
import 'package:health_pro/core/theme/app_spacing.dart';
import 'package:health_pro/presentation/features/billing/billing_controller.dart';
import 'package:health_pro/presentation/features/billing/tier_matrix.dart';
import 'package:health_pro/presentation/features/billing/tier_palette.dart';
import 'package:health_pro/presentation/l10n/app_localizations.dart';

/// "Compare Features" and the table under it: one column per tier on sale, one row per entitlement
/// the backend actually enforces (see [compareRows]).
class PaywallCompare extends StatelessWidget {
  const PaywallCompare({required this.billing, super.key});

  final BillingController billing;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Obx(() {
      final tiers = billing.tiers;
      if (tiers.isEmpty) return const SizedBox.shrink();

      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // The heading and the toggle share a row until the toggle no longer fits beside it,
          // which at 200 % text is immediately — a Wrap rather than a Row that would overflow.
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.sm,
            children: [
              Text(
                l.premiumCompare,
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              _PeriodToggle(billing: billing),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          _CompareTable(tiers: tiers),
        ],
      );
    });
  }
}

/// Switches the small line under every price between per-month and per-year. It changes how the
/// SAME prices are read, never which prices are shown — there is one price matrix and the server
/// owns it.
class _PeriodToggle extends StatelessWidget {
  const _PeriodToggle({required this.billing});

  final BillingController billing;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);

    return Obx(
      () => SegmentedButton<bool>(
        showSelectedIcon: false,
        segments: [
          ButtonSegment<bool>(value: false, label: Text(l.premiumViewMonthly)),
          ButtonSegment<bool>(value: true, label: Text(l.premiumViewYearly)),
        ],
        selected: {billing.perYear.value},
        onSelectionChanged: (s) => billing.perYear.value = s.first,
      ),
    );
  }
}

class _CompareTable extends StatelessWidget {
  const _CompareTable({required this.tiers});

  final List<String> tiers;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final rows = compareRows(l);

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.cardLarge),
        border: Border.all(color: theme.colorScheme.outline),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          _HeaderRow(tiers: tiers),
          for (final row in rows) _FeatureRow(row: row, tiers: tiers, last: row == rows.last),
        ],
      ),
    );
  }
}

class _HeaderRow extends StatelessWidget {
  const _HeaderRow({required this.tiers});

  final List<String> tiers;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Container(
      color: theme.colorScheme.surfaceContainerHighest,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      child: Row(
        children: [
          Expanded(
            flex: _labelFlex,
            child: Text(
              l.premiumFeatureColumn,
              style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          for (final tier in tiers)
            Expanded(
              child: Builder(
                builder: (context) {
                  final style = tierStyleFor(tier, theme.brightness);
                  return Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      ExcludeSemantics(
                        child: Icon(style.icon, size: AppSpacing.lg, color: style.ink),
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Flexible(
                        child: Text(
                          tierLabel(l, tier),
                          style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

/// The feature column is wider than a tier column: it holds a sentence, they hold a tick.
const _labelFlex = 3;

class _FeatureRow extends StatelessWidget {
  const _FeatureRow({required this.row, required this.tiers, required this.last});

  final CompareRow row;
  final List<String> tiers;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      constraints: const BoxConstraints(minHeight: AppSpacing.minTouchTarget),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      decoration: BoxDecoration(
        border: last ? null : Border(bottom: BorderSide(color: theme.colorScheme.outline)),
      ),
      child: Row(
        children: [
          Expanded(
            flex: _labelFlex,
            child: Row(
              children: [
                ExcludeSemantics(
                  child: Icon(
                    row.icon,
                    size: AppSpacing.lg,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(child: Text(row.label, style: theme.textTheme.bodySmall)),
              ],
            ),
          ),
          for (final tier in tiers)
            Expanded(
              child: _Cell(cell: row.byTier[tier], label: row.label, tier: tier),
            ),
        ],
      ),
    );
  }
}

/// A figure where the tiers differ by amount, a tick or a cross where they differ at all.
///
/// The cross is `close`, not a red X: docs/05 §6 keeps red for destructive actions, and "your tier
/// does not include this" is not a failure the user committed.
class _Cell extends StatelessWidget {
  const _Cell({required this.cell, required this.label, required this.tier});

  final TierCell? cell;
  final String label;
  final String tier;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final value = cell;

    // A tier the server priced that this table has no row for shows nothing rather than a cross —
    // a cross would claim the backend excludes something nobody has said either way about.
    if (value == null) return const SizedBox.shrink();

    final semantics = '${tierLabel(l, tier)}: $label';

    if (value.figure case final figure?) {
      return Semantics(
        label: '$semantics — $figure',
        excludeSemantics: true,
        child: Center(
          child: Text(
            figure,
            textAlign: TextAlign.center,
            style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
      );
    }

    return Semantics(
      label: semantics,
      // The tick IS the value here, so it is read as a checkbox rather than skipped as decoration.
      checked: value.included,
      child: Center(
        child: Icon(
          value.included ? Icons.check_circle : Icons.cancel_outlined,
          size: AppSpacing.xl,
          color: value.included ? AppColors.success : theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
