import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:health_pro/core/theme/app_colors.dart';
import 'package:health_pro/core/theme/app_spacing.dart';
import 'package:health_pro/presentation/features/billing/billing_controller.dart';
import 'package:health_pro/presentation/features/billing/paywall_sheet.dart';
import 'package:health_pro/presentation/l10n/app_localizations.dart';

/// The pill in the heading. Rendered ONLY when the server has said this account is FREE —
/// docs/11 §10 names "upgrade CTA while subscribed" as a shipped defect of the old build, and
/// unknown-yet is treated as subscribed, not as a sales opportunity.
class PremiumPill extends StatelessWidget {
  const PremiumPill({required this.billing, super.key});

  final BillingController billing;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);

    // The reference pill is the quiet green tint with the brand green on it, not a gold banner —
    // the scheme's secondaryContainer pair, so dark mode gets its own tint for free.
    final scheme = theme.colorScheme;

    return Obx(() {
      if (!billing.showPremium) return const SizedBox.shrink();

      return Material(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        child: InkWell(
          onTap: () => PaywallSheet.show(context, billing),
          borderRadius: BorderRadius.circular(AppRadius.pill),
          child: Container(
            constraints: const BoxConstraints(minHeight: AppSpacing.minTouchTarget),
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.workspace_premium,
                  size: AppSpacing.lg,
                  color: scheme.onSecondaryContainer,
                ),
                const SizedBox(width: AppSpacing.xs),
                Text(
                  l.premiumGo,
                  style: theme.textTheme.labelLarge?.copyWith(color: scheme.onSecondaryContainer),
                ),
                Icon(Icons.chevron_right, size: AppSpacing.lg, color: scheme.onSecondaryContainer),
              ],
            ),
          ),
        ),
      );
    });
  }
}

/// The banner at the foot of the plan. Same gate as the pill; the features named are the REAL
/// entitlement gaps between tiers (api tiers.ts) — regenerations, alternates, PDF export,
/// priority support — never a promise the backend cannot keep.
class PremiumBanner extends StatelessWidget {
  const PremiumBanner({required this.billing, super.key});

  final BillingController billing;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Obx(() {
      if (!billing.showPremium) return const SizedBox.shrink();

      final features = [
        (Icons.refresh, l.premiumFeatRegen),
        (Icons.swap_horiz, l.premiumFeatAlternates),
        (Icons.picture_as_pdf_outlined, l.premiumFeatExport),
        (Icons.support_agent, l.premiumFeatSupport),
      ];

      return Padding(
        padding: const EdgeInsets.only(top: AppSpacing.lg),
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.lg),
          decoration: BoxDecoration(
            color: AppColors.primary,
            borderRadius: BorderRadius.circular(AppRadius.cardLarge),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.workspace_premium,
                    color: AppColors.warning,
                    size: AppSpacing.xl,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      l.premiumTitle,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: AppColors.darkOnSurface,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                l.premiumBody,
                style: theme.textTheme.bodySmall?.copyWith(color: AppColors.darkMuted),
              ),
              const SizedBox(height: AppSpacing.md),
              Wrap(
                spacing: AppSpacing.md,
                runSpacing: AppSpacing.sm,
                children: [
                  for (final (icon, label) in features)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(icon, size: AppSpacing.lg, color: AppColors.accentBright),
                        const SizedBox(width: AppSpacing.xs),
                        Text(
                          label,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: AppColors.darkOnSurface,
                          ),
                        ),
                      ],
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: theme.colorScheme.surface,
                      foregroundColor: AppColors.primary,
                    ),
                    onPressed: () => PaywallSheet.show(context, billing),
                    child: Text(l.premiumGo),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Text(
                      l.premiumTrial,
                      style: theme.textTheme.bodySmall?.copyWith(color: AppColors.darkMuted),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    });
  }
}
