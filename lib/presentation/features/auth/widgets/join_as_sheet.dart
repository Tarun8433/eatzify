import 'package:flutter/material.dart';
import 'package:health_pro/core/theme/app_assets.dart';
import 'package:health_pro/core/theme/app_spacing.dart';
import 'package:health_pro/domain/entities/profession.dart';
import 'package:health_pro/presentation/features/auth/widgets/auth_fields.dart';
import 'package:health_pro/presentation/l10n/app_localizations.dart';

/// "Who are you?" — asked when someone taps Create account, before the sign-up form.
///
/// Both answers lead to the same form: the account is the same either way. The answer is
/// remembered so onboarding asks "do you work in fitness or nutrition?" only of a professional
/// (see [JoinAs]).
class JoinAsSheet extends StatelessWidget {
  const JoinAsSheet({super.key});

  /// The answer, or null when the sheet was dismissed.
  static Future<JoinAs?> show(BuildContext context) {
    return showModalBottomSheet<JoinAs>(
      context: context,
      // Taller than half the screen and scrolls inside itself; without this it is capped at half
      // height and the second card is out of reach.
      isScrollControlled: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.sheet)),
      ),
      builder: (_) => const JoinAsSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    void choose(JoinAs answer) => Navigator.of(context).pop(answer);

    _JoinCard individual({required bool pinFoot}) => _JoinCard(
      pinFoot: pinFoot,
      art: AppAssets.joinIndividual,
      title: l.joinIndividualTitle,
      body: l.joinIndividualBody,
      points: [
        (Icons.restaurant_rounded, l.joinIndividualPoint1),
        (Icons.track_changes_rounded, l.joinIndividualPoint2),
        (Icons.bar_chart_rounded, l.joinIndividualPoint3),
        (Icons.favorite_rounded, l.joinIndividualPoint4),
      ],
      cta: l.joinIndividualCta,
      wash: theme.colorScheme.secondaryContainer,
      ink: theme.colorScheme.primary,
      onInk: theme.colorScheme.onPrimary,
      onTap: () => choose(JoinAs.individual),
    );
    _JoinCard professional({required bool pinFoot}) => _JoinCard(
      pinFoot: pinFoot,
      art: AppAssets.joinProfessional,
      title: l.joinProfessionalTitle,
      body: l.joinProfessionalBody,
      points: [
        (Icons.groups_rounded, l.joinProfessionalPoint1),
        (Icons.insights_rounded, l.joinProfessionalPoint2),
        (Icons.event_note_rounded, l.joinProfessionalPoint3),
        (Icons.verified_rounded, l.joinProfessionalPoint4),
      ],
      cta: l.joinProfessionalCta,
      // The warm pair, as on the paywall's second card (D-160): the other choice at a glance.
      wash: theme.colorScheme.tertiaryContainer,
      ink: theme.colorScheme.onTertiaryContainer,
      onInk: theme.colorScheme.tertiaryContainer,
      onTap: () => choose(JoinAs.professional),
    );

    return FractionallySizedBox(
      heightFactor: _sheetHeightFactor,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(child: _Badge(label: l.signUpTitle)),
            const SizedBox(height: AppSpacing.md),
            Text(
              l.joinSheetTitle,
              textAlign: TextAlign.center,
              style: theme.textTheme.displayLarge?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              l.joinSheetSubtitle,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.5,
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            LayoutBuilder(
              builder: (context, constraints) {
                // Side by side where two cards fit; stacked on a narrow phone or at large text,
                // where two columns would each be a word wide (rule 12).
                final stacked =
                    constraints.maxWidth < AppSizes.tierCardMin * 2 + AppSpacing.md ||
                    MediaQuery.textScalerOf(context).scale(1) > AppSizes.heroStackTextScale;
                if (stacked) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      individual(pinFoot: false),
                      const SizedBox(height: AppSpacing.md),
                      professional(pinFoot: false),
                    ],
                  );
                }
                return IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(child: individual(pinFoot: true)),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(child: professional(pinFoot: true)),
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: AppSpacing.lg),
            AuthLinkRow(
              lead: l.signUpHaveAccount,
              action: l.loginSignIn,
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      ),
    );
  }
}

/// Short of full height, so the strip of the page left showing says this is a sheet you can leave.
const _sheetHeightFactor = 0.92;

class _Badge extends StatelessWidget {
  const _Badge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.xs),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.onSecondaryContainer),
      ),
    );
  }
}

/// One answer: the art, what it means, and the button. The whole card is the button — the drawn
/// "Continue" is its label, not a second target to find.
class _JoinCard extends StatelessWidget {
  const _JoinCard({
    required this.pinFoot,
    required this.art,
    required this.title,
    required this.body,
    required this.points,
    required this.cta,
    required this.wash,
    required this.ink,
    required this.onInk,
    required this.onTap,
  });

  /// Side by side, the button sits at the card's foot so the two line up. Stacked, the card is as
  /// tall as its content — a spacer there has no height to fill, and throws.
  final bool pinFoot;
  final String art;
  final String title;
  final String body;
  final List<(IconData, String)> points;
  final String cta;
  final Color wash;
  final Color ink;
  final Color onInk;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return MergeSemantics(
      child: Semantics(
        button: true,
        child: Material(
          color: wash,
          borderRadius: BorderRadius.circular(AppRadius.cardLarge),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ExcludeSemantics(
                    child: AspectRatio(
                      aspectRatio: _artAspect,
                      child: Image.asset(
                        art,
                        fit: BoxFit.contain,
                        // A missing asset must not take the sign-up path down with it.
                        errorBuilder: (context, _, _) => const SizedBox.shrink(),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    title,
                    style: theme.textTheme.headlineMedium?.copyWith(
                      color: ink,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    body,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  for (final (icon, label) in points)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                      child: Row(
                        children: [
                          ExcludeSemantics(
                            child: Container(
                              height: AppSizes.choiceDisc,
                              width: AppSizes.choiceDisc,
                              decoration: BoxDecoration(
                                color: theme.colorScheme.surface,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(icon, size: AppSpacing.lg, color: ink),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(child: Text(label, style: theme.textTheme.bodySmall)),
                        ],
                      ),
                    ),
                  if (pinFoot) const Spacer(),
                  const SizedBox(height: AppSpacing.sm),
                  Container(
                    constraints: const BoxConstraints(minHeight: AppSpacing.minTouchTarget),
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                      vertical: AppSpacing.sm,
                    ),
                    decoration: BoxDecoration(
                      color: ink,
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            cta,
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: onInk,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        ExcludeSemantics(
                          child: Icon(
                            Icons.arrow_forward_rounded,
                            size: AppSpacing.lg,
                            color: onInk,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The supplied art's own proportions (1347 × 1167 and 1374 × 1145), so neither is letterboxed.
const _artAspect = 1.17;
