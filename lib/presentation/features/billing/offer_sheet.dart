import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:health_pro/core/config/site_links.dart';
import 'package:health_pro/core/format/rupees.dart';
import 'package:health_pro/core/theme/app_spacing.dart';
import 'package:health_pro/core/widgets/app_sheet.dart';
import 'package:health_pro/core/widgets/state_views.dart';
import 'package:health_pro/core/widgets/view_state.dart';
import 'package:health_pro/domain/entities/billing.dart';
import 'package:health_pro/presentation/features/billing/offer_controller.dart';
import 'package:health_pro/presentation/features/billing/paywall_sheet.dart';
import 'package:health_pro/presentation/features/billing/tier_palette.dart';
import 'package:health_pro/presentation/l10n/app_localizations.dart';
import 'package:health_pro/presentation/widgets/site_link.dart';
import 'package:intl/intl.dart';

/// D-265: "A special offer for you" — the sheet a personal-offer link opens.
///
/// Sized to its content and scrolling inside itself, so at 200 % text the buy button is scrolled
/// to rather than pushed off the sheet (rule 12).
class OfferSheet extends StatelessWidget {
  const OfferSheet({required this.controller, super.key});

  final OfferController controller;

  static Future<void> show(BuildContext context, OfferController controller) {
    controller.load();
    return showAppSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => OfferSheet(controller: controller),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.sm,
          AppSpacing.sm,
          AppSpacing.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    l.offerSheetTitle,
                    style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                  tooltip: l.premiumClose,
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.sm),
              child: Obx(
                () => switch (controller.state.value) {
                  Loading<PersonalOffer>() => const LoadingView(lines: 2),
                  // The server's one OFFER_NOT_FOUND message, verbatim, and the way out (rule 7).
                  Failed<PersonalOffer>(:final failure) => FailedView(
                    failure: failure,
                    onRetry: () => Navigator.of(context).pop(),
                    retryLabel: l.premiumClose,
                  ),
                  // Never produced: a missing offer is the server's 404, shown as Failed above.
                  Empty<PersonalOffer>() => const SizedBox.shrink(),
                  Ready<PersonalOffer>(:final data) => _OfferDetails(
                    controller: controller,
                    offer: data,
                  ),
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OfferDetails extends StatelessWidget {
  const _OfferDetails({required this.controller, required this.offer});

  final OfferController controller;
  final PersonalOffer offer;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final dates = DateFormat.yMMMd(Localizations.localeOf(context).toLanguageTag());
    final regular = offer.regularPricePaise;
    final expires = offer.expiresAt;
    final errorStyle = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l.offerPlan(tierLabel(l, offer.tier), l.premiumMonths(offer.months)),
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.sm,
          crossAxisAlignment: WrapCrossAlignment.end,
          children: [
            Obx(
              () => Text(
                _price(l, controller.storePrice.value),
                style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            if (regular != null)
              Semantics(
                label: l.offerRegularPrice(Rupees.fromPaise(regular)),
                excludeSemantics: true,
                child: Text(
                  Rupees.fromPaise(regular),
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    decoration: TextDecoration.lineThrough,
                  ),
                ),
              ),
          ],
        ),
        if (expires != null) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            l.offerEnds(dates.format(expires)),
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
        const SizedBox(height: AppSpacing.lg),
        Obx(() {
          final busy = controller.buying.value;
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (controller.storeProblem.value case final problem?)
                _Line(storeProblemText(l, problem), style: errorStyle),
              if (controller.gatewayUnavailable.value)
                _Line(l.billingGatewayUnavailable, style: errorStyle),
              // Rule 7: whatever the server or gateway refused with, in its own words.
              if (controller.buyError.value case final message?) _Line(message, style: errorStyle),
              FilledButton(
                onPressed: busy ? null : () => _buy(context),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                  minimumSize: const Size.fromHeight(AppSizes.primaryButton),
                ),
                child: Text(busy ? l.premiumPayWorking : l.offerBuy, textAlign: TextAlign.center),
              ),
            ],
          );
        }),
        const SizedBox(height: AppSpacing.md),
        AgreementLine(
          lead: l.legalAgreePay,
          links: [
            (label: l.legalTerms, uri: SiteLinks.terms),
            (label: l.legalRefunds, uri: SiteLinks.refunds),
          ],
        ),
      ],
    );
  }

  /// Cashfree: the server's amount. Play: Play's own figure for the offer, or no figure at all —
  /// never the server's catalogue copy, which could disagree with what Play's sheet then charges.
  ///
  /// [storePrice] is read by the caller on every path, so its `Obx` always has something to watch.
  String _price(AppLocalizations l, String? storePrice) {
    if (offer.isPlay) return storePrice ?? l.offerSpecialPrice;
    final paise = offer.pricePaise;
    return paise == null ? l.offerSpecialPrice : Rupees.fromPaise(paise);
  }

  Future<void> _buy(BuildContext context) async {
    final done = await controller.buy();
    if (done && context.mounted) Navigator.of(context).pop();
  }
}

class _Line extends StatelessWidget {
  const _Line(this.text, {required this.style});

  final String text;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
    child: Text(text, textAlign: TextAlign.center, style: style),
  );
}
