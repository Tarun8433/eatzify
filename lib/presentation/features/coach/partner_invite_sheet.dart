import 'package:flutter/material.dart';
import 'package:health_pro/core/theme/app_spacing.dart';
import 'package:health_pro/core/widgets/app_card.dart';
import 'package:health_pro/presentation/l10n/app_localizations.dart';

/// The partner offer, shown the moment someone says they work in fitness or nutrition.
///
/// A sheet rather than a step in the funnel. Onboarding is already a dozen screens of being asked
/// things, and an extra page about a different product reads as an advert; arriving as a reply to
/// the answer just given, it reads as a reply.
///
/// **It changes nothing.** docs/12 §6 makes level 1 an accepted agreement and level 2 a human
/// reading documents, and neither belongs half-way through somebody's health onboarding. The sheet
/// explains the route and says where it starts.
abstract final class PartnerInviteSheet {
  static Future<void> show(BuildContext context) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => const _PartnerInviteBody(),
  );
}

class _PartnerInviteBody extends StatelessWidget {
  const _PartnerInviteBody();

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final benefits = <(IconData, String)>[
      (Icons.payments_outlined, l.partnerBenefitEarn),
      (Icons.group_outlined, l.partnerBenefitClients),
      // Worded against docs/10 §2, not against what sounds best. The `progress` scope is "weight
      // series, adherence %, steps, streaks" — so weight, steps and adherence are honest, and
      // anything implying the whole diary is not: a verified coach sees an adherence PERCENTAGE,
      // and only a coaching partner with a grant sees the food logs themselves.
      (Icons.timeline_outlined, l.partnerBenefitTrack),
      (Icons.verified_outlined, l.partnerBenefitBadge),
      (Icons.insights_outlined, l.partnerBenefitDashboard),
    ];

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
        MediaQuery.of(context).viewInsets.bottom + AppSpacing.xl,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              ExcludeSemantics(
                child: Container(
                  height: AppSizes.ringSmall,
                  width: AppSizes.ringSmall,
                  decoration: BoxDecoration(
                    color: scheme.secondaryContainer,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.handshake_outlined, color: scheme.onSecondaryContainer),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  l.partnerInviteTitle,
                  style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(l.partnerInviteSubtitle, style: theme.textTheme.bodyMedium),
          const SizedBox(height: AppSpacing.lg),

          for (final (icon, text) in benefits)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(icon, color: scheme.primary, size: AppSpacing.xl),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(child: Text(text, style: theme.textTheme.bodyMedium)),
                ],
              ),
            ),

          const SizedBox(height: AppSpacing.sm),
          // The honest half. docs/12 §6 forbids implying accreditation, so this says what actually
          // happens next rather than what a badge would look like.
          HintCard(icon: Icons.info_outline, text: l.partnerInviteAfter),
          const SizedBox(height: AppSpacing.lg),

          SizedBox(
            height: AppSizes.primaryButton,
            child: FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(l.partnerInviteContinue),
            ),
          ),
        ],
      ),
    );
  }
}
