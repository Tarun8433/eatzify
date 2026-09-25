import 'package:flutter/material.dart';
import 'package:health_pro/core/theme/app_spacing.dart';
import 'package:health_pro/core/widgets/skeleton.dart';
import 'package:health_pro/presentation/l10n/app_localizations.dart';

/// What Home looks like before the diary arrives (D-162).
///
/// The generic `LoadingView` — three grey bars — was the wrong shape for this screen: the day
/// landed and the page jumped from three bars to a hero, a tile row and a list of meals. A
/// skeleton's job is to be the page with the words missing, so this mirrors `_Today` block for
/// block, at the same paddings, the same 0.56 hero fraction and the same breakpoint.
///
/// Everything here is decoration standing in for content that has not arrived, so the whole thing
/// is one semantics node saying so rather than a dozen unlabelled boxes a screen reader would
/// read out as nothing at all.
class HomeSkeleton extends StatelessWidget {
  const HomeSkeleton({super.key});

  /// `_Hero._textFraction`. The cards take this much and the walker has the rest.
  static const _textFraction = 0.56;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: AppLocalizations.of(context).commonLoading,
      excludeSemantics: true,
      child: Skeleton(
        child: ListView(
          // `_Today`'s own padding — no top inset, the day bar sits under the heading.
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.screenH,
            0,
            AppSpacing.screenH,
            AppSpacing.xxl,
          ),
          children: const [
            _DayBarRow(),
            SizedBox(height: AppSpacing.sm),
            _HeroBlock(),
            SizedBox(height: AppSpacing.lg),
            _SectionHeadingRow(),
            SizedBox(height: AppSpacing.xs),
            _TileRow(),
            SizedBox(height: AppSpacing.lg),
            SkeletonBox(width: _headingWidth, height: _heading),
            SizedBox(height: AppSpacing.md),
            _MealRow(),
            _MealRow(),
            _MealRow(),
          ],
        ),
      ),
    );
  }

  static const _heading = 20.0;
  static const _headingWidth = 140.0;
}

/// `< Today >` — an arrow, a label, an arrow.
class _DayBarRow extends StatelessWidget {
  const _DayBarRow();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        SkeletonBox.circle(size: AppSpacing.xl),
        SkeletonBox(width: 96, height: 20),
        SkeletonBox.circle(size: AppSpacing.xl),
      ],
    ),
  );
}

/// The calorie card with the water card overlapping its foot, in the left text fraction of the
/// row — the walker's side stays empty because he is painted behind the page, not in it.
class _HeroBlock extends StatelessWidget {
  const _HeroBlock();

  static const _calorieCard = 132.0;
  static const _waterCard = 64.0;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // `_Hero`'s own rule: the column takes the full width when the screen is narrow or the
        // text is large, and its share of the row otherwise.
        final textScale = MediaQuery.textScalerOf(context).scale(1);
        final stacked =
            constraints.maxWidth < AppSizes.heroBreakpoint ||
            textScale >= AppSizes.heroStackTextScale;

        final column = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            const SkeletonBox(height: _calorieCard, radius: AppRadius.cardLarge),
            // The real water card is translated up over the green card's foot.
            Transform.translate(
              offset: const Offset(0, -AppSpacing.md),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                child: SkeletonBox(height: _waterCard, radius: AppRadius.cardLarge),
              ),
            ),
          ],
        );

        if (stacked) return column;

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: constraints.maxWidth * HomeSkeleton._textFraction, child: column),
          ],
        );
      },
    );
  }
}

/// "Macronutrients" on the left, "Details ›" on the right.
class _SectionHeadingRow extends StatelessWidget {
  const _SectionHeadingRow();

  @override
  Widget build(BuildContext context) => const Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [SkeletonBox(width: 150, height: 20), SkeletonBox(width: 72, height: 20)],
  );
}

/// The macro tiles. Three across, two-by-two below `_NutrientTiles`' own breakpoint.
class _TileRow extends StatelessWidget {
  const _TileRow();

  static const _tile = 172.0;
  static const _count = 3;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final perRow = constraints.maxWidth < AppSizes.heroBreakpoint ? 2 : _count;
        final width = (constraints.maxWidth - AppSpacing.sm * (perRow - 1)) / perRow;

        return Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            for (var i = 0; i < _count; i++)
              SkeletonBox(width: width, height: _tile, radius: AppRadius.tile),
          ],
        );
      },
    );
  }
}

/// One logged entry: a disc, the food's name over its portion, and the calories.
class _MealRow extends StatelessWidget {
  const _MealRow();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.only(bottom: AppSpacing.md),
    child: Row(
      children: [
        SkeletonBox.circle(size: AppSizes.ringSmall),
        SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SkeletonBox(),
              SizedBox(height: AppSpacing.sm),
              SkeletonBox(width: 120, height: AppSpacing.md),
            ],
          ),
        ),
        SizedBox(width: AppSpacing.md),
        SkeletonBox(width: 56),
      ],
    ),
  );
}
