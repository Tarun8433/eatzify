import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:health_pro/core/format/rupees.dart';
import 'package:health_pro/core/theme/app_spacing.dart';
import 'package:health_pro/core/widgets/app_card.dart';
import 'package:health_pro/core/widgets/state_views.dart';
import 'package:health_pro/core/widgets/view_state.dart';
import 'package:health_pro/domain/entities/billing.dart';
import 'package:health_pro/domain/repositories/billing_repository.dart';
import 'package:health_pro/presentation/features/billing/billing_controller.dart';
import 'package:health_pro/presentation/features/billing/paywall_sheet.dart';
import 'package:health_pro/presentation/features/billing/subscription_controller.dart';
import 'package:health_pro/presentation/features/billing/tier_palette.dart';
import 'package:health_pro/presentation/l10n/app_localizations.dart';
import 'package:intl/intl.dart';

/// "Your plan" (docs/14 §6). What the server says this account holds, and the things docs/11 says
/// a person may do about it: take the free week, stop the renewal, or move up mid-term.
class SubscriptionPage extends StatelessWidget {
  const SubscriptionPage({super.key});

  /// The tier a mid-term upgrade goes to, and for how long. One rung, because docs/11 §7 is about
  /// moving UP from what you hold — picking any cell of the matrix is what the paywall is for.
  static const upgradeTier = 'PRO';
  static const upgradeMonths = 3;

  static Future<void>? open() => Get.to<void>(
    () => const SubscriptionPage(),
    binding: BindingsBuilder<void>(() {
      Get.lazyPut(() => SubscriptionController(billing: Get.find<BillingRepository>()));
    }),
  );

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = Get.find<SubscriptionController>();

    return Scaffold(
      appBar: AppBar(title: Text(l.subscriptionTitle)),
      body: Obx(
        () => switch (c.state.value) {
          Loading<SubscriptionState>() => const LoadingView(),
          Failed<SubscriptionState>(:final failure) => FailedView(
            failure: failure,
            onRetry: c.load,
          ),
          // Not produced: the server answers FREE rather than nothing. Rendered anyway (rule 6).
          Empty<SubscriptionState>() => EmptyView(title: l.subscriptionFree),
          Ready<SubscriptionState>(:final data) => _Body(controller: c, plan: data),
        },
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.controller, required this.plan});

  final SubscriptionController controller;
  final SubscriptionState plan;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final dates = DateFormat.yMMMMd(Localizations.localeOf(context).toLanguageTag());

    return RefreshIndicator(
      onRefresh: () => controller.load(quiet: true),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.lg,
          AppSpacing.lg,
          AppSpacing.xxl,
        ),
        children: [
          AppCard(
            accent: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  plan.isFree ? l.subscriptionFree : tierLabel(l, plan.tier),
                  style: theme.textTheme.headlineSmall,
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(_when(l, dates), style: theme.textTheme.bodyMedium),
                // docs/11 §8: a plan above ₹15,000 renews with the bank's approval, every time.
                if (plan.requiresAfa) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text(l.subscriptionAfaNote, style: muted),
                ],
              ],
            ),
          ),
          if (_trouble(l) case final message?) ...[
            const SizedBox(height: AppSpacing.md),
            HintCard(icon: Icons.info_outline, text: message),
          ],
          const SizedBox(height: AppSpacing.lg),

          // Rule 7: the server's own words for anything it refused.
          Obx(() {
            final message = controller.error.value;
            return message == null
                ? const SizedBox.shrink()
                : Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.md),
                    child: Text(
                      message,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
                    ),
                  );
          }),

          if (plan.isFree && plan.trialAvailable) _TrialCard(controller: controller),
          if (plan.isFree && !plan.trialAvailable)
            Text(l.subscriptionTrialUsed, style: muted, textAlign: TextAlign.center),

          if (!plan.isFree && plan.tier != SubscriptionPage.upgradeTier) ...[
            const SizedBox(height: AppSpacing.md),
            Obx(
              () => SizedBox(
                height: AppSizes.primaryButton,
                child: FilledButton.icon(
                  onPressed: controller.busy.value ? null : () => _upgrade(context, controller),
                  icon: const Icon(Icons.arrow_upward),
                  label: Text(l.subscriptionUpgrade(tierLabel(l, SubscriptionPage.upgradeTier))),
                ),
              ),
            ),
          ],

          const SizedBox(height: AppSpacing.md),
          SizedBox(
            height: AppSizes.primaryButton,
            child: OutlinedButton.icon(
              onPressed: () => _openPaywall(context),
              icon: const Icon(Icons.list_alt_outlined),
              label: Text(l.subscriptionSeePlans),
            ),
          ),

          // docs/09 §7: cancelling stops the renewal; it never takes away what was paid for.
          if (plan.willRenew) ...[
            const SizedBox(height: AppSpacing.sm),
            Obx(
              () => TextButton(
                onPressed: controller.busy.value ? null : () => _cancel(context, controller, dates),
                child: Text(l.subscriptionCancelRenewal),
              ),
            ),
          ],
          if (plan.isFree) ...[
            const SizedBox(height: AppSpacing.lg),
            Text(l.subscriptionFreeBody, style: muted),
          ],
        ],
      ),
    );
  }

  /// The one line under the tier: when it renews, when it stops, or when the trial ends.
  String _when(AppLocalizations l, DateFormat dates) {
    final ends = plan.endsAt;
    if (plan.isFree || ends == null) return l.subscriptionFreeBody;
    if (plan.isTrial) return l.subscriptionTrialUntil(dates.format(ends));
    return plan.willRenew
        ? l.subscriptionRenewsOn(dates.format(ends))
        : l.subscriptionEndsOn(dates.format(ends));
  }

  /// docs/11 §5's two unhappy states, said plainly and without blame (docs/05 §6).
  String? _trouble(AppLocalizations l) => switch (plan.status) {
    'past_due' => l.subscriptionPastDue,
    'grace' => l.subscriptionGrace,
    _ => null,
  };

  static void _openPaywall(BuildContext context) {
    if (!Get.isRegistered<BillingController>()) return;
    PaywallSheet.show(context, Get.find<BillingController>());
  }

  static Future<void> _cancel(
    BuildContext context,
    SubscriptionController controller,
    DateFormat dates,
  ) async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final ends = (controller.state.value as Ready<SubscriptionState>).data.endsAt;

    final stop = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(l.subscriptionCancelTitle),
        content: Text(l.subscriptionCancelBody(ends == null ? '—' : dates.format(ends))),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialog).pop(false),
            child: Text(l.subscriptionCancelKeep),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialog).pop(true),
            child: Text(l.subscriptionCancelConfirm),
          ),
        ],
      ),
    );
    if (stop != true) return;

    await controller.cancelRenewal();
    final now = controller.state.value;
    if (controller.error.value != null || now is! Ready<SubscriptionState>) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            l.subscriptionCancelled(now.data.endsAt == null ? '—' : dates.format(now.data.endsAt!)),
          ),
        ),
      );
  }

  /// docs/11 §7: the arithmetic is on screen before anything is charged.
  static Future<void> _upgrade(BuildContext context, SubscriptionController controller) async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final quote = await controller.quote(
      tier: SubscriptionPage.upgradeTier,
      months: SubscriptionPage.upgradeMonths,
    );
    if (quote == null || !context.mounted) return;

    final go = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => _QuoteSheet(quote: quote),
    );
    if (go != true) return;

    final done = await controller.confirmUpgrade(tier: quote.tier, months: quote.months);
    if (!done) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(l.subscriptionUpgraded(tierLabel(l, quote.tier)))));
  }
}

/// docs/11 §6's free week, offered once per number.
class _TrialCard extends StatelessWidget {
  const _TrialCard({required this.controller});

  final SubscriptionController controller;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l.subscriptionStartTrial, style: theme.textTheme.titleMedium),
          const SizedBox(height: AppSpacing.xs),
          Text(l.subscriptionTrialBody, style: theme.textTheme.bodyMedium),
          const SizedBox(height: AppSpacing.md),
          Text(l.subscriptionPickTrialTier, style: theme.textTheme.bodySmall),
          const SizedBox(height: AppSpacing.sm),
          Obx(
            () => Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                for (final tier in const ['BASIC', 'PRO'])
                  FilledButton.tonal(
                    onPressed: controller.busy.value ? null : () => controller.startTrial(tier),
                    child: Text(tierLabel(l, tier)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The proration, item by item. docs/11 §7: "Show the arithmetic on screen; opaque proration
/// generates tickets."
class _QuoteSheet extends StatelessWidget {
  const _QuoteSheet({required this.quote});

  final UpgradeQuote quote;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              l.subscriptionUpgradeTitle(tierLabel(l, quote.tier)),
              style: theme.textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.lg),
            _Line(
              label: l.subscriptionUpgradePrice(tierLabel(l, quote.tier), '${quote.months}'),
              value: Rupees.format(quote.pricePaise ~/ 100),
            ),
            const SizedBox(height: AppSpacing.sm),
            _Line(
              label: l.subscriptionUpgradeCredit('${quote.remainingDays}'),
              value: '− ${Rupees.format(quote.creditPaise ~/ 100)}',
            ),
            const Divider(height: AppSpacing.xl),
            _Line(
              label: l.subscriptionUpgradeDue,
              value: Rupees.format(quote.amountDuePaise ~/ 100),
              strong: true,
            ),
            const SizedBox(height: AppSpacing.lg),
            SizedBox(
              height: AppSizes.primaryButton,
              child: FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: Text(l.subscriptionUpgradeConfirm),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.label, required this.value, this.strong = false});

  final String label;
  final String value;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = strong
        ? theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)
        : theme.textTheme.bodyMedium;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: Text(label, style: style)),
        const SizedBox(width: AppSpacing.md),
        Text(value, style: style),
      ],
    );
  }
}
