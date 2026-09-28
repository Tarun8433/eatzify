import 'package:flutter/material.dart';
import 'package:health_pro/core/theme/app_spacing.dart';
import 'package:health_pro/core/widgets/press_scale.dart';

/// A single-select or multi-select option row.
///
/// It was also a compact `.chip` for a while (D-88), for the sixteen conditions. D-110 gave those
/// rows a glyph each and the chip lost its last caller: a chip can hold a label and nothing else.
/// Deleted rather than kept for a future screen that has not asked for it.
///
/// 48 dp minimum target and a real `Semantics` state, so a screen reader announces selection rather
/// than leaving it to a colour difference (docs/14 §5).
///
/// **It moves when you touch it (D-103).** This is the most-tapped control in the app — roughly
/// forty taps to get through onboarding — and every one of them used to be a dead, instant flip.
/// Three things happen now: the tile shrinks under the finger, the border and fill tween rather
/// than snapping, and the check scales in past its size and settles. None of it is decoration —
/// each answers "did that register?" inside the 100 ms before a colour change is readable.
class ChoiceTile extends StatelessWidget {
  const ChoiceTile({
    required this.label,
    required this.selected,
    required this.onTap,
    super.key,
    this.description,
    this.icon,
    this.compact = false,
    this.multiSelect = false,
  });

  final String label;
  final String? description;

  /// Shown in a tinted circle at the leading edge (D-104). Decoration, not meaning — the label
  /// carries that — but it is what turns a row of white pills into a list of distinguishable
  /// options, and it is how the eye finds the one it wants without reading all of them.
  final IconData? icon;

  /// Half-width layout (D-112): a bare glyph instead of a tinted disc, and tighter padding.
  ///
  /// The disc costs 44 pt plus its gap. In a full-width row that is nothing; in half a phone,
  /// beside a mark and two paddings, it left 55 pt for the label and "Wheat / gluten" wrapped onto
  /// three lines. The glyph alone still tells the cells apart, which is all it was ever for.
  final bool compact;

  final bool selected;
  final bool multiSelect;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Semantics(
      inMutuallyExclusiveGroup: !multiSelect,
      selected: selected,
      button: true,
      child: Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
        child: PressScale(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.card),
          child: AnimatedContainer(
            duration: AppMotion.normal,
            curve: AppMotion.enter,
            constraints: const BoxConstraints(minHeight: AppSpacing.minTouchTarget),
            // `sm`, not `md`. With a 44 pt disc inside it the row stood 68 pt tall, and three of
            // them filled half a phone for three one-word answers — the gender step read as the
            // heaviest question in the funnel when it is the quickest. At `sm` around a 32 pt disc
            // the row lands on the 48 dp floor exactly, so it is as thin as rule 12 allows.
            padding: EdgeInsets.symmetric(
              horizontal: compact ? AppSpacing.md : AppSpacing.lg,
              vertical: AppSpacing.sm,
            ),
            decoration: BoxDecoration(
              // The tint, not the deep primary at 8 % (D-107). Dark green over a warm cream page
              // mixes to a grey-brown, and the chosen row read as disabled rather than as chosen.
              color: selected ? scheme.secondaryContainer.withValues(alpha: 0.4) : scheme.surface,
              borderRadius: BorderRadius.circular(AppRadius.tile),
              border: Border.all(
                color: selected ? scheme.primary : scheme.outline,
                width: selected ? 2 : 1,
              ),
              // Unselected options are lifted off the page; the selected one is not. Depth reads as
              // "these are waiting for you", and the chosen one has stopped waiting — its border
              // and tint say so more clearly than another shadow could.
              boxShadow: selected ? const [] : AppElevation.card(theme.brightness),
            ),
            child: Row(
              children: [
                if (icon != null && compact) ...[
                  Icon(
                    icon,
                    size: AppSpacing.xl,
                    color: selected ? scheme.primary : scheme.onSecondaryContainer,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                ] else if (icon != null) ...[
                  // The disc FILLS when the option is chosen (D-107). The reference does it, and
                  // it is the difference between a row that is ticked and a row that is lit: the
                  // eye finds the answer from across the screen without reading the mark.
                  AnimatedContainer(
                    duration: AppMotion.normal,
                    curve: AppMotion.enter,
                    height: AppSizes.choiceDisc,
                    width: AppSizes.choiceDisc,
                    decoration: BoxDecoration(
                      color: selected ? scheme.primary : scheme.secondaryContainer,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      icon,
                      size: AppSpacing.lg,
                      color: selected ? scheme.onPrimary : scheme.onSecondaryContainer,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                        ),
                      ),
                      if (description != null) ...[
                        const SizedBox(height: AppSpacing.xs),
                        Text(description!, style: theme.textTheme.bodySmall),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                _Mark(selected: selected, multiSelect: multiSelect),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The tick, which pops rather than appears (D-103, D-104).
///
/// The overshoot is the whole point: a check that scales straight to 1.0 reads as a repaint, and
/// one that goes slightly past and settles reads as a thing that landed. `easeOutBack` is the
/// curve the teardown names for exactly this.
class _Mark extends StatelessWidget {
  const _Mark({required this.selected, required this.multiSelect});

  final bool selected;
  final bool multiSelect;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    // Two marks, because they mean two different things (D-106). A multi-select is a tick — a
    // filled disc that is the only saturated thing on the card, so the eye lands on it to confirm
    // the tap. A single-select is a RING WITH A DOT: the reference draws it that way, and it is
    // the one shape that says "and not the others" before the label is read.
    final mark = !selected
        ? Container(
            height: AppSpacing.xl,
            width: AppSpacing.xl,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: scheme.outline),
            ),
          )
        : multiSelect
        ? Container(
            height: AppSpacing.xl,
            width: AppSpacing.xl,
            decoration: BoxDecoration(color: scheme.primary, shape: BoxShape.circle),
            child: Icon(Icons.check, size: AppSpacing.lg, color: scheme.onPrimary),
          )
        : Container(
            height: AppSpacing.xl,
            width: AppSpacing.xl,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: scheme.primary, width: 2),
            ),
            child: Center(
              child: Container(
                height: AppSpacing.md,
                width: AppSpacing.md,
                decoration: BoxDecoration(color: scheme.primary, shape: BoxShape.circle),
              ),
            ),
          );

    // Only the SELECTED state pops. Animating the empty box on every deselect would draw the eye
    // to the option someone just rejected.
    if (!selected || !AppMotion.enabled(context)) return mark;

    return TweenAnimationBuilder<double>(
      // Keyed so re-selecting a different option replays it on the new one.
      key: ValueKey(multiSelect),
      tween: Tween(begin: 0, end: 1),
      duration: AppMotion.normal,
      curve: Curves.easeOutBack,
      builder: (context, t, child) => Transform.scale(scale: t, child: child),
      child: mark,
    );
  }
}
