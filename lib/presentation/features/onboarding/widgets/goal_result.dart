import 'package:flutter/material.dart';
import 'package:health_pro/core/theme/app_assets.dart';
import 'package:health_pro/core/theme/app_spacing.dart';
import 'package:health_pro/core/widgets/animated_count.dart';
import 'package:health_pro/core/widgets/app_card.dart';
import 'package:health_pro/core/widgets/weight_curve.dart';
import 'package:health_pro/presentation/l10n/app_localizations.dart';

/// The gap between where someone is and where they want to be (D-101, redesigned in D-110).
///
/// **It projects nothing.** The two endpoints are the weights the user typed and the curve between
/// them is easing, not a forecast — no rate, no date, no "by when". CLAUDE.md rule 2 puts every
/// target on the server, and the engine has not run yet.
///
/// The one claim on the screen is [inHealthyRange], and it is a restatement of the rule the app
/// already enforced: `ValidateOnboarding.goalWeightKg` rejects a target under BMI 18.5 with no
/// override, so a goal that reached this screen has passed that floor. Anything warmer than that —
/// "great choice", "healthy and sustainable" — would be the app judging a clinical outcome it has
/// no basis for, which docs/05 §6 and rule 7 both forbid.
class GoalResultView extends StatelessWidget {
  const GoalResultView({
    required this.startKg,
    required this.targetKg,
    required this.inHealthyRange,
    super.key,
    this.chromeOnly = false,
    this.healthyLowKg,
    this.healthyHighKg,
  });

  final double? startKg;
  final double? targetKg;

  /// The healthy band for this height, straight from the same domain helper the form validates
  /// against. When both ends are given, the note names the numbers instead of only saying "inside
  /// the range" — still shown only when [inHealthyRange] is true, so docs/05 §6's silence about a
  /// goal outside it is unchanged.
  final double? healthyLowKg;
  final double? healthyHighKg;

  /// Drops the headline and the encouragement, leaving the card (D-114). The summary step shows
  /// the curve a second time, and the words that introduce it belong to the step where they land
  /// for the first time — repeated, they read as the app padding out a recap.
  final bool chromeOnly;

  /// Whether the target sits inside the healthy weight band for this height. Null when the height
  /// or the target is missing and the question cannot be answered — in which case nothing is said.
  final bool? inHealthyRange;

  /// Where the note's anchor sits on the curve. Two thirds along, which is where the curve has
  /// flattened enough for a card above it not to cover the line.
  static const _markerAt = 0.62;

  /// Past this text scale the card stops arranging things side by side: the note moves under the
  /// curve instead of over it, and the two weights stack. Same threshold the Home hero uses.
  static bool _roomy(BuildContext context) =>
      MediaQuery.textScalerOf(context).scale(1) < AppSizes.heroStackTextScale;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final start = startKg;
    final target = targetKg ?? start;
    // A target is optional (see the basics step), so with none given there is no gap and the
    // screen says so rather than showing a flat line and a zero.
    final delta = (start == null || target == null) ? 0.0 : start - target;
    final kg = delta.abs().toStringAsFixed(1);

    final full = delta > 0
        ? l.onboardingResultTitle(kg)
        : delta < 0
        ? l.onboardingResultGain(kg)
        : l.onboardingResultHold;
    final emphasis = delta > 0
        ? l.onboardingResultLoseShort(kg)
        : delta < 0
        ? l.onboardingResultGainShort(kg)
        : l.onboardingResultHoldShort;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!chromeOnly)
          _Header(
            lead: l.onboardingResultLead,
            emphasis: emphasis,
            spoken: full,
            body: l.onboardingResultBody,
          ),
        if (!chromeOnly) const SizedBox(height: AppSpacing.xl),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // The reference heads the card with words, not chips: a bold title and one warm
              // line under it. The heart is drawn, not typed — no emoji as iconography.
              Text(
                l.onboardingResultProgressTitle,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(text: l.onboardingResultProgressSub),
                    WidgetSpan(
                      alignment: PlaceholderAlignment.middle,
                      child: Padding(
                        padding: const EdgeInsets.only(left: AppSpacing.xs),
                        child: ExcludeSemantics(
                          child: Icon(
                            Icons.favorite,
                            size: AppSpacing.lg,
                            color: theme.colorScheme.secondary,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              _CurveWithNote(
                startKg: start ?? 0,
                targetKg: target ?? 0,
                noteTitle: l.onboardingResultGoalChip,
                // The note only appears when there is something true to say — and it names the
                // band when the numbers are known.
                note: !(inHealthyRange ?? false)
                    ? null
                    : (healthyLowKg != null && healthyHighKg != null)
                    ? l.onboardingResultRangeNote(
                        healthyLowKg!.toStringAsFixed(0),
                        healthyHighKg!.toStringAsFixed(0),
                      )
                    : l.onboardingResultHealthyNote,
              ),
              const SizedBox(height: AppSpacing.lg),
              _Ends(
                fromChip: l.onboardingResultCurrentChip,
                fromKg: start,
                toChip: l.onboardingResultGoalChip,
                toKg: target,
                between: l.onboardingResultOnWay,
              ),
            ],
          ),
        ),
        if (!chromeOnly) ...[
          const SizedBox(height: AppSpacing.lg),
          // Encouragement, not a claim: it says nothing about weight, a rate or a date. docs/05 §6
          // rules out judgement and implied failure, not warmth.
          _Tip(title: l.onboardingResultTipTitle, body: l.onboardingResultTipBody),
        ],
      ],
    );
  }
}

/// The headline in two parts, with the number carrying the colour, and the art beside it.
class _Header extends StatelessWidget {
  const _Header({
    required this.lead,
    required this.emphasis,
    required this.spoken,
    required this.body,
  });

  final String lead;
  final String emphasis;

  /// The whole sentence, for a screen reader. The split into two coloured lines is a visual
  /// arrangement; read aloud in pieces it would come out as two fragments.
  final String spoken;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final title = Semantics(
      header: true,
      label: spoken,
      child: ExcludeSemantics(
        child: Text.rich(
          TextSpan(
            children: [
              TextSpan(text: '$lead\n'),
              TextSpan(
                text: emphasis,
                style: TextStyle(color: theme.colorScheme.primary),
              ),
              WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: Padding(
                  padding: const EdgeInsets.only(left: AppSpacing.xs),
                  child: Icon(
                    Icons.eco,
                    size: (theme.textTheme.displayLarge?.fontSize ?? 32) * 0.55,
                    color: theme.colorScheme.secondary,
                  ),
                ),
              ),
            ],
          ),
          style: theme.textTheme.displayLarge?.copyWith(fontWeight: FontWeight.w800, height: 1.2),
        ),
      ),
    );

    final subtitle = Text(
      body,
      style: theme.textTheme.bodyMedium?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
        height: 1.5,
      ),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        // The same share the sign-in screen gives its art (D-111).
        final art = (constraints.maxWidth * AppSizes.heroArtFraction).clamp(
          0.0,
          AppSizes.heroArtMax,
        );
        // Past this scale the words need the whole width, and a picture is the first thing that
        // can be given up for them (rule 12). Same threshold the Home hero stacks at.
        final stacked = MediaQuery.textScalerOf(context).scale(1) >= AppSizes.heroStackTextScale;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (stacked)
              title
            else
              // A Stack rather than a Row: the art overlaps the headline's box by the amount the
              // PNG's own transparent margin allows, which is where the width for a two-line
              // headline comes from.
              SizedBox(
                width: constraints.maxWidth,
                child: Stack(
                  alignment: Alignment.centerRight,
                  children: [
                    Align(
                      alignment: Alignment.centerRight,
                      child: ExcludeSemantics(
                        child: Container(
                          width: art,
                          height: art,
                          decoration: BoxDecoration(
                            color: theme.colorScheme.secondaryContainer.withValues(alpha: 0.5),
                            shape: BoxShape.circle,
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(AppSpacing.sm),
                            child: Image.asset(
                              AppAssets.goalHero,
                              fit: BoxFit.contain,
                              // A missing asset must not take the step down with it, and nothing
                              // stands in: the picture says nothing the headline has not.
                              errorBuilder: (context, _, _) => const SizedBox.shrink(),
                            ),
                          ),
                        ),
                      ),
                    ),
                    // Drawn over the disc, and starting at the margin where reading starts.
                    SizedBox(
                      width: constraints.maxWidth,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: SizedBox(
                          width: constraints.maxWidth * AppSizes.heroTextFraction,
                          child: title,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: AppSpacing.md),
            subtitle,
          ],
        );
      },
    );
  }
}

/// The curve, with the reference's "Now" and "Goal" flags over its two ends and an optional note
/// hanging off its anchor.
class _CurveWithNote extends StatelessWidget {
  const _CurveWithNote({
    required this.startKg,
    required this.targetKg,
    required this.note,
    required this.noteTitle,
  });

  final double startKg;
  final double targetKg;
  final String? note;
  final String noteTitle;

  /// Headroom the curve leaves above its start dot so the "Now" flag can stand over it.
  static const _flagRoom = 56.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);

    final roomy = GoalResultView._roomy(context);
    Widget curve = WeightCurve(
      startKg: startKg,
      targetKg: targetKg,
      topInset: roomy ? _flagRoom : AppSpacing.xl,
      // The anchor is only worth drawing when something is hanging off it in the same box.
      markerAt: note == null || !roomy ? null : GoalResultView._markerAt,
    );

    if (roomy) {
      // Decoration for a screen reader — the weights below already speak both ends.
      //
      // Each flag is anchored at its dot's x (the curve insets its ends by AppSpacing.xl) and
      // then pulled back by half its own width, so the tail points AT the dot whatever the
      // translated label's width. Pinned to the Stack's corners, "Now" hung in space beside its
      // dot with the arrow aiming at nothing. Clip.none because a wide label may run a few
      // pixels past the chart's box, into the card's padding.
      curve = Stack(
        clipBehavior: Clip.none,
        children: [
          curve,
          Positioned(
            left: AppSpacing.xl,
            top: 0,
            child: FractionalTranslation(
              translation: const Offset(-0.5, 0),
              child: _CurveFlag(l.onboardingResultFrom),
            ),
          ),
          // Above the end dot, which sits at the bottom inset.
          Positioned(
            right: AppSpacing.xl,
            bottom: AppSpacing.xl + AppSpacing.md,
            child: FractionalTranslation(
              translation: const Offset(0.5, 0),
              child: _CurveFlag(l.onboardingResultGoalFlag),
            ),
          ),
        ],
      );
    }

    if (note == null) return curve;

    final card = Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(AppRadius.tile),
        boxShadow: AppElevation.raised(theme.brightness),
        border: Border.all(color: theme.colorScheme.outline),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ExcludeSemantics(
            child: Container(
              width: AppSpacing.xxl,
              height: AppSpacing.xxl,
              decoration: BoxDecoration(
                color: theme.colorScheme.secondaryContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.track_changes,
                size: AppSpacing.lg,
                color: theme.colorScheme.onSecondaryContainer,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  noteTitle,
                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(note!, style: theme.textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );

    // Under the curve once the type is large: over it, the note would be taller than the chart it
    // is pointing at and would cover the descent it is about.
    if (!roomy) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          curve,
          const SizedBox(height: AppSpacing.md),
          card,
        ],
      );
    }

    return Stack(
      clipBehavior: Clip.none,
      children: [
        curve,
        // Just over half the width — enough for the note to sit two lines tall, which keeps its
        // bottom edge above the sine descent it points at. At 0.45 it ran three lines deep and
        // its corner sat on the line.
        Positioned(top: 0, right: 0, width: MediaQuery.sizeOf(context).width * 0.52, child: card),
      ],
    );
  }
}

/// One of the reference's flags over the curve — "Now" above the start dot, "Goal" above the end
/// ring: a filled label with a tail aiming at its dot. Decoration only.
class _CurveFlag extends StatelessWidget {
  const _CurveFlag(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return ExcludeSemantics(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xs),
            decoration: BoxDecoration(
              color: scheme.primary,
              borderRadius: BorderRadius.circular(AppRadius.card),
            ),
            child: Text(
              label,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: scheme.onPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Icon(Icons.arrow_drop_down, size: AppSpacing.lg, color: scheme.primary),
        ],
      ),
    );
  }
}

/// The two weights under the curve, and the reassurance between them.
class _Ends extends StatelessWidget {
  const _Ends({
    required this.fromChip,
    required this.fromKg,
    required this.toChip,
    required this.toKg,
    required this.between,
  });

  final String fromChip;
  final double? fromKg;
  final String toChip;
  final double? toKg;
  final String between;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final from = _End(chip: fromChip, kg: fromKg);
    final to = _End(chip: toChip, kg: toKg, emphasis: true);

    // Stacked at large text scales: two four-character weights at 44 pt do not share a phone's
    // width, and the flourish between them is the first thing worth giving up (rule 12).
    if (!GoalResultView._roomy(context)) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          from,
          const SizedBox(height: AppSpacing.lg),
          to,
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        from,
        // The reference's sparkle pill between the two weights.
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.sm,
                ),
                decoration: BoxDecoration(
                  color: theme.colorScheme.secondaryContainer.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(AppRadius.tile),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ExcludeSemantics(
                      child: Icon(
                        Icons.auto_awesome,
                        size: AppSpacing.lg,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Flexible(
                      child: Text(
                        between,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        to,
      ],
    );
  }
}

/// One end of the curve: the weight, counting up, and which end it is said in words below it —
/// the reference drops the Now/Target micro-labels (the flags on the curve carry those) and lets
/// the number lead.
class _End extends StatelessWidget {
  const _End({required this.chip, required this.kg, this.emphasis = false});

  final String chip;
  final double? kg;
  final bool emphasis;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final align = emphasis ? CrossAxisAlignment.end : CrossAxisAlignment.start;

    return Column(
      crossAxisAlignment: align,
      children: [
        AnimatedCount(
          value: kg ?? 0,
          fractionDigits: 1,
          suffix: ' kg',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w800,
            color: emphasis ? theme.colorScheme.primary : null,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          chip,
          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

/// The encouragement under the card. Not a button: there is nowhere for it to go, and an arrow
/// that leads nowhere is worse than no arrow (the same reason the sign-in screen drops its back
/// arrow on the first step).
class _Tip extends StatelessWidget {
  const _Tip({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(AppRadius.cardLarge),
      ),
      child: Row(
        children: [
          ExcludeSemantics(
            child: Container(
              width: AppSizes.ringSmall,
              height: AppSizes.ringSmall,
              decoration: BoxDecoration(color: scheme.primary, shape: BoxShape.circle),
              child: Icon(
                Icons.emoji_events_outlined,
                size: AppSpacing.xl,
                color: scheme.onPrimary,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  body,
                  style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
