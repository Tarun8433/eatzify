import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:health_pro/core/format/rupees.dart';
import 'package:health_pro/core/theme/app_spacing.dart';
import 'package:health_pro/core/widgets/app_card.dart';
import 'package:health_pro/core/widgets/state_views.dart';
import 'package:health_pro/core/widgets/view_state.dart';
import 'package:health_pro/domain/entities/billing.dart';
import 'package:health_pro/presentation/features/billing/billing_controller.dart';
import 'package:health_pro/presentation/features/billing/paywall_compare.dart';
import 'package:health_pro/presentation/features/billing/paywall_plan_cards.dart';
import 'package:health_pro/presentation/features/billing/tier_palette.dart';
import 'package:health_pro/presentation/l10n/app_localizations.dart';

/// How much of the screen the sheet may take. Short of full height on purpose: the strip of the
/// page left showing is what makes it a sheet you can dismiss rather than a screen you are stuck
/// on, and the paywall is the last place to make someone hunt for the way out.
const _sheetHeightFactor = 0.92;

/// The plans and their prices — the server's own, from `GET /billing/prices`, in paise formatted
/// the Indian way. Checkout does not exist server-side yet (D-134), and the sheet says so rather
/// than drawing a pay button that goes nowhere.
class PaywallSheet extends StatelessWidget {
  const PaywallSheet({required this.billing, super.key});

  final BillingController billing;

  static Future<void> show(BuildContext context, BillingController billing) {
    billing.loadPrices();
    return showModalBottomSheet<void>(
      context: context,
      // The sheet is taller than half the screen and scrolls inside itself; without this it is
      // capped at half height and the compare table is unreachable.
      isScrollControlled: true,
      builder: (_) => PaywallSheet(billing: billing),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FractionallySizedBox(
      heightFactor: _sheetHeightFactor,
      child: SafeArea(
        child: Column(
          children: [
            const _Handle(),
            const _Header(),
            Expanded(child: _Body(billing: billing)),
            _PayButton(billing: billing),
          ],
        ),
      ),
    );
  }
}

class _Handle extends StatelessWidget {
  const _Handle();

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Container(
      margin: const EdgeInsets.only(top: AppSpacing.sm, bottom: AppSpacing.xs),
      height: AppSpacing.xs,
      width: AppSpacing.xxl,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.outline,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
    ),
  );
}

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    // The header wears PRO's mark, because premium is what the sheet is selling.
    final style = tierStyleFor('PRO', theme.brightness);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.sm,
        AppSpacing.md,
      ),
      child: Row(
        children: [
          ExcludeSemantics(
            child: Container(
              height: AppSizes.ringSmall,
              width: AppSizes.ringSmall,
              decoration: BoxDecoration(color: style.tint, shape: BoxShape.circle),
              child: Icon(style.icon, color: style.ink, size: AppSpacing.xl),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l.premiumSheetTitle,
                  style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
                Text(
                  l.premiumSheetSubtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close),
            tooltip: l.premiumClose,
          ),
        ],
      ),
    );
  }
}

/// The four states (rule 6). The old sheet showed a spinner whenever the list was empty, which
/// meant a refused request and an empty catalogue both rendered as loading forever.
class _Body extends StatelessWidget {
  const _Body({required this.billing});

  final BillingController billing;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);

    return Obx(() {
      final state = billing.priceState.value;

      return switch (state) {
        Loading<List<TierPrice>>() => const LoadingView(),
        Empty<List<TierPrice>>() => EmptyView(title: l.premiumPlansEmpty),
        Failed<List<TierPrice>>(:final failure) => FailedView(
          failure: failure,
          onRetry: () => billing.loadPrices(force: true),
        ),
        Ready<List<TierPrice>>() => _Plans(billing: billing),
      };
    });
  }
}

class _Plans extends StatelessWidget {
  const _Plans({required this.billing});

  final BillingController billing;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Shown only when the SERVER says it cannot take money (D-194). A live build that kept
          // saying "opening soon" would be the same defect as a dead pay button, pointed the other
          // way.
          Obx(
            () => billing.canTakePayment
                ? const SizedBox.shrink()
                : Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.lg),
                    child: HintCard(
                      icon: Icons.info_outline,
                      title: l.premiumComingSoon,
                      text: l.premiumComingSoonBody,
                    ),
                  ),
          ),
          TierPlanCards(billing: billing),
          const SizedBox(height: AppSpacing.xl),
          PaywallCompare(billing: billing),
        ],
      ),
    );
  }
}

/// The sheet's one action: buy the selected row.
///
/// It says the PRICE, because a button reading "Continue" on a screen of ten prices is a button
/// somebody taps to find out what it costs. On a stub build (D-194) there is no gateway to open,
/// so the label says the plan is being unlocked for testing rather than implying money moved.
class _PayButton extends StatelessWidget {
  const _PayButton({required this.billing});

  final BillingController billing;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Obx(() {
      // Nothing to act on until there are plans to act on.
      if (billing.priceState.value is! Ready<List<TierPrice>>) {
        return const SizedBox.shrink();
      }

      final chosen = billing.selectedPricePaise;
      final busy = billing.buying.value;
      final live = billing.canTakePayment;

      return Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // D-236: the offer code, priced server-side. Deliberately NOT read back into this
            // Obx — typing must not rebuild the sheet under the keyboard.
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: TextField(
                onChanged: (value) => billing.couponCode.value = value,
                textCapitalization: TextCapitalization.characters,
                decoration: InputDecoration(
                  labelText: l.premiumCouponLabel,
                  isDense: true,
                ),
              ),
            ),
            // Rule 7: whatever the server refused with, in its own words.
            if (billing.buyError.value case final message?)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: Text(
                  message,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
                ),
              ),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: chosen == null || busy ? null : billing.purchase,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                  minimumSize: const Size.fromHeight(AppSizes.primaryButton),
                ),
                child: Text(switch ((busy, chosen)) {
                  (true, _) => l.premiumPayWorking,
                  // Paise on the wire, rupees on the button — the same conversion the price
                  // cards do, and the only place the two units meet on this screen.
                  (false, final paise?) when live => l.premiumPayNow(Rupees.format(paise ~/ 100)),
                  (false, final paise?) => l.premiumPayStub(Rupees.format(paise ~/ 100)),
                  _ => l.premiumPayPick,
                }),
              ),
            ),
          ],
        ),
      );
    });
  }
}
