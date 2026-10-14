import 'package:flutter/material.dart';
import 'package:health_pro/core/theme/app_assets.dart';
import 'package:health_pro/core/theme/app_spacing.dart';
import 'package:health_pro/presentation/l10n/app_localizations.dart';

/// The mark, the name and the promise, top left of the sign-in screen.
class LoginBrand extends StatelessWidget {
  const LoginBrand({super.key});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final ink = theme.colorScheme.primary;

    return Row(
      children: [
        ExcludeSemantics(
          child: SizedBox(
            height: AppSizes.ringSmall,
            width: AppSizes.ringSmall,
            child: Image.asset(AppAssets.logo, fit: BoxFit.cover, alignment: Alignment.topCenter),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l.appTitle,
                style: theme.textTheme.headlineMedium?.copyWith(
                  color: ink,
                  fontWeight: FontWeight.w800,
                  height: 1.1,
                ),
              ),
              // One line, always: a tagline that wraps under a logo reads as a layout fault.
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(l.loginTagline, maxLines: 1, style: theme.textTheme.bodySmall),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Three things the app is for, under the headline: an icon beside a two-line label, as the design
/// has it. Each label breaks after its first word, so an item is only as wide as its longest word
/// and three fit across a 360 dp phone. A Wrap, so a narrower phone or large text moves the last
/// one to a second line instead of overflowing (rule 12).
class LoginPerks extends StatelessWidget {
  const LoginPerks({super.key});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);

    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        _Perk(icon: Icons.eco_outlined, label: l.loginPerkNutrition),
        _Perk(icon: Icons.favorite_border_rounded, label: l.loginPerkLifestyle),
        _Perk(icon: Icons.bar_chart_rounded, label: l.loginPerkInsights),
      ],
    );
  }
}

/// Smaller than the usual 32 pt disc: three of these and their labels share one 312 pt row.
const _perkTile = AppSpacing.xl + AppSpacing.xs;

class _Perk extends StatelessWidget {
  const _Perk({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ExcludeSemantics(
          child: Container(
            height: _perkTile,
            width: _perkTile,
            decoration: BoxDecoration(
              color: theme.colorScheme.secondaryContainer.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(AppRadius.card),
            ),
            child: Icon(icon, size: AppSpacing.lg, color: theme.colorScheme.primary),
          ),
        ),
        const SizedBox(width: AppSpacing.sm - AppSpacing.xs / 2),
        // Flexible so a long word at large text wraps inside the row instead of overflowing it.
        Flexible(
          child: Text(
            // "Better nutrition" → "Better / nutrition". The break is the design's, not a wrap.
            label.replaceFirst(' ', '\n'),
            style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurface),
          ),
        ),
      ],
    );
  }
}

/// "New to Eatzify?" at the foot of sign-in: a raised panel holding one card, the way in to
/// sign-up. The card opens the sheet that asks who you are (see `JoinAsSheet`), so the question is
/// asked once, there, rather than here and again there.
class JoinPanel extends StatelessWidget {
  const JoinPanel({required this.onCreate, super.key});

  final VoidCallback? onCreate;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.md,
      ),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(AppRadius.sheet),
        boxShadow: AppElevation.card(theme.brightness),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l.loginNoAccount,
            style: theme.textTheme.headlineMedium?.copyWith(
              color: scheme.primary,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(l.loginJoinSubtitle, style: theme.textTheme.bodySmall),
          const SizedBox(height: AppSpacing.md),
          Material(
            color: scheme.secondaryContainer,
            borderRadius: BorderRadius.circular(AppRadius.cardLarge),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onCreate,
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Row(
                  children: [
                    const ExcludeSemantics(child: _Faces()),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            l.loginCreateAccount,
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: scheme.primary,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          Text(l.loginJoinWho, style: theme.textTheme.bodySmall),
                        ],
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    ExcludeSemantics(
                      child: Container(
                        height: AppSizes.choiceDisc,
                        width: AppSizes.choiceDisc,
                        decoration: BoxDecoration(color: scheme.primary, shape: BoxShape.circle),
                        child: Icon(
                          Icons.arrow_forward_rounded,
                          size: AppSpacing.lg,
                          color: scheme.onPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Two discs overlapping by about half.
const _facesWidthFactor = 1.45;

/// The two answers' art, overlapped, as a hint of the question the card asks.
class _Faces extends StatelessWidget {
  const _Faces();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    Widget face(String asset, Color wash) => Container(
      height: AppSizes.ringSmall,
      width: AppSizes.ringSmall,
      decoration: BoxDecoration(
        color: wash,
        shape: BoxShape.circle,
        border: Border.all(color: scheme.surface, width: AppSpacing.xs / 2),
      ),
      clipBehavior: Clip.antiAlias,
      child: Image.asset(
        asset,
        fit: BoxFit.cover,
        alignment: Alignment.topCenter,
        errorBuilder: (context, _, _) => const SizedBox.shrink(),
      ),
    );

    return SizedBox(
      width: AppSizes.ringSmall * _facesWidthFactor,
      height: AppSizes.ringSmall,
      child: Stack(
        children: [
          face(AppAssets.joinIndividual, scheme.surface),
          Positioned(right: 0, child: face(AppAssets.joinProfessional, scheme.tertiaryContainer)),
        ],
      ),
    );
  }
}
