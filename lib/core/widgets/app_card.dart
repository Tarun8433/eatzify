import 'package:flutter/material.dart';
import 'package:health_pro/core/theme/app_colors.dart';
import 'package:health_pro/core/theme/app_spacing.dart';
import 'package:health_pro/core/widgets/press_scale.dart';

/// The surface every grouped block sits on. docs/14 §5 design language.
///
/// One widget rather than a `Container` per screen: the radius, padding and border are decisions
/// that must not drift between Home, Progress and You. If a card needs to look different, the
/// token changes here and every screen follows.
class AppCard extends StatelessWidget {
  const AppCard({
    required this.child,
    super.key,
    this.padding = const EdgeInsets.all(AppSpacing.lg),
    this.onTap,
    this.accent = false,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;

  /// Draws the card as the emphasised one on a screen — the "today" summary, not every card.
  ///
  /// Emphasis is a lighter surface plus a hairline accent border, NOT a saturated fill. The first
  /// version used Material 3's derived `primaryContainer`, which rendered a mid-green at 1.8:1
  /// against the number on it — every piece of text on that card failed CLAUDE.md rule 12.
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final decorated = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: accent ? scheme.surfaceContainerHighest : scheme.surface,
        borderRadius: BorderRadius.circular(AppRadius.cardLarge),
        // Depth AND an edge (D-100). A white card is 1.08:1 against the cream page, so on its own
        // the border was doing all the separating and every card read as a flat outline. The
        // shadow lifts it off the page; the border keeps the edge legible where a shadow cannot
        // be seen — in dark mode, and for anyone with contrast preferences turned up.
        boxShadow: AppElevation.card(theme.brightness),
        border: accent
            ? Border.all(
                color:
                    (theme.brightness == Brightness.dark ? AppColors.accentBright : scheme.primary)
                        .withValues(alpha: 0.35),
              )
            : Border.all(color: scheme.outline),
      ),
      child: child,
    );

    if (onTap == null) return decorated;

    return PressScale(
      onTap: onTap!,
      borderRadius: BorderRadius.circular(AppRadius.cardLarge),
      child: decorated,
    );
  }
}

/// A tinted card that explains rather than reports (D-106, D-109).
///
/// Quieter than [AppCard] on purpose: no shadow, no white fill — it is a note on the page, not
/// another surface competing with the answers above it. Used where a screen would otherwise show a
/// bare grey sentence, which reads as a caption nobody looks at.
///
/// Two tones, because the page has two kinds of note. The default is the brand tint: a hint, a
/// prompt, something the app is offering. [HintCard.important] is warm, and is for the one on
/// every onboarding screen that says this is not medical advice — a safety note that reads as
/// another green hint is a safety note nobody registers (docs/05 §7).
///
/// The icon is decoration and is excluded from semantics; the text carries the meaning.
class HintCard extends StatelessWidget {
  const HintCard({
    required this.icon,
    required this.text,
    super.key,
    this.title,
    this.dense = false,
  }) : _warm = false;

  const HintCard.important({required this.icon, required this.text, required this.title, super.key})
    : _warm = true,
      dense = false;

  final IconData icon;
  final String text;

  /// A heading above the body. The important note has one; a one-line hint does not need one.
  final String? title;

  /// Smaller type, tighter padding, smaller disc. For a note that must be present without being
  /// a paragraph the eye has to climb over — the Plan tab's advice line, the server's target note
  /// (D-137). The words are unchanged; only their presence shrinks.
  final bool dense;

  final bool _warm;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    // The warm tone is `warmCoral` — already in the palette as the one non-green accent — laid on
    // at a tenth, with `warning` on the glyph. Nothing new invented for one card.
    final fill = _warm
        ? AppColors.warmCoral.withValues(alpha: 0.10)
        : scheme.secondaryContainer.withValues(alpha: 0.45);
    final edge = _warm ? AppColors.warmCoral.withValues(alpha: 0.28) : scheme.secondaryContainer;
    final glyph = _warm ? AppColors.warning : scheme.onSecondaryContainer;

    final disc = dense ? AppSpacing.xxl : AppSizes.ringSmall;

    return Container(
      padding: EdgeInsets.all(dense ? AppSpacing.md : AppSpacing.lg),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(AppRadius.tile),
        border: Border.all(color: edge),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ExcludeSemantics(
            child: Container(
              height: disc,
              width: disc,
              decoration: BoxDecoration(color: scheme.surface, shape: BoxShape.circle),
              child: Icon(icon, size: dense ? AppSpacing.lg : AppSpacing.xl, color: glyph),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (title != null) ...[
                  Text(
                    title!,
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                ],
                Text(
                  text,
                  style: (dense ? theme.textTheme.bodySmall : theme.textTheme.bodyMedium)?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
