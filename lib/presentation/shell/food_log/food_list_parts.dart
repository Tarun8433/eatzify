import 'package:flutter/material.dart';
import 'package:health_pro/core/theme/app_colors.dart';
import 'package:health_pro/core/theme/app_spacing.dart';
import 'package:health_pro/core/widgets/app_card.dart';
import 'package:health_pro/core/widgets/food_image.dart';
import 'package:health_pro/domain/entities/food.dart';
import 'package:health_pro/domain/entities/onboarding_enums.dart';
import 'package:health_pro/presentation/features/onboarding/enum_labels.dart';
import 'package:health_pro/presentation/l10n/app_localizations.dart';

/// The category chips above the list (D-238). Each is one or more docs/03 §4 food groups, sent to
/// the server as `group=` — "Protein" is four groups because nobody looks for "pulse" by name.
enum FoodGroupChip {
  all(null, Icons.restaurant),
  vegetables(['veg'], Icons.eco_outlined),
  grains(['cereal'], Icons.rice_bowl_outlined),
  protein(['pulse', 'meat', 'fish', 'egg'], Icons.egg_alt_outlined),
  fruits(['fruit'], Icons.spa_outlined),
  dairy(['dairy'], Icons.local_drink_outlined),
  snacks(['prepared'], Icons.fastfood_outlined);

  const FoodGroupChip(this.groups, this.icon);

  /// Null is the whole table.
  final List<String>? groups;
  final IconData icon;

  String label(AppLocalizations l) => switch (this) {
    all => l.logGroupAll,
    vegetables => l.logGroupVegetables,
    grains => l.logGroupGrains,
    protein => l.logGroupProtein,
    fruits => l.logGroupFruits,
    dairy => l.logGroupDairy,
    snacks => l.logGroupSnacks,
  };
}

/// A row of group chips that scrolls sideways. It sizes to its content rather than a fixed band, so
/// a 200 % font grows the chips instead of clipping them (rule 12).
class FoodGroupChips extends StatelessWidget {
  const FoodGroupChips({required this.selected, required this.onChanged, super.key});

  final FoodGroupChip selected;
  final ValueChanged<FoodGroupChip> onChanged;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final chip in FoodGroupChip.values) ...[
            if (chip != FoodGroupChip.values.first) const SizedBox(width: AppSpacing.sm),
            _GroupChip(chip: chip, selected: chip == selected, onTap: () => onChanged(chip)),
          ],
        ],
      ),
    );
  }
}

class _GroupChip extends StatelessWidget {
  const _GroupChip({required this.chip, required this.selected, required this.onTap});

  final FoodGroupChip chip;
  final bool selected;
  final VoidCallback onTap;

  static const _minWidth = 76.0;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final fg = selected ? scheme.onPrimary : scheme.onSurfaceVariant;

    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? scheme.primary : scheme.surface,
        borderRadius: BorderRadius.circular(AppRadius.tile),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.tile),
          child: Container(
            constraints: const BoxConstraints(
              minWidth: _minWidth,
              minHeight: AppSpacing.minTouchTarget,
            ),
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.tile),
              border: selected ? null : Border.all(color: scheme.outline.withValues(alpha: 0.6)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ExcludeSemantics(
                  child: Icon(chip.icon, size: AppSpacing.xl, color: fg),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(chip.label(l), style: theme.textTheme.labelMedium?.copyWith(color: fg)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The white pill the search field sits in.
///
/// Separate from the field because `inputDecorationTheme` is the app's ANSWER field — filled
/// white, tile radius, hairline outline — and on a white sheet that is invisible. This one carries
/// its own edge and its own shadow.
class SearchSurface extends StatelessWidget {
  const SearchSurface({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: theme.colorScheme.outline.withValues(alpha: 0.5)),
        boxShadow: AppElevation.card(theme.brightness),
      ),
      child: child,
    );
  }
}

/// A section's title, what it is for, and the one thing that can be done to it.
///
/// Two sections use it — the quick-add shelf and the list — and they must not drift: a screen
/// whose two headings size their type differently reads as two screens stapled together.
class SectionHeading extends StatelessWidget {
  const SectionHeading({
    required this.title,
    required this.subtitle,
    required this.icon,
    super.key,
    this.action,
  });

  final String title;
  final String subtitle;

  /// Decoration beside the title. Excluded from semantics — the words carry the meaning.
  final IconData icon;

  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  ExcludeSemantics(
                    child: Icon(icon, size: AppSpacing.lg, color: theme.colorScheme.secondary),
                  ),
                ],
              ),
              Text(subtitle, style: theme.textTheme.bodySmall),
            ],
          ),
        ),
        if (action != null) action!,
      ],
    );
  }
}

/// The shelf of tiles above the list: the foods a user is most likely to be here for, one tap
/// from the portion sheet.
///
/// A row of four rather than a horizontal scroller. Four is what fits a phone's width at a
/// readable tile size, and a scroller that only ever holds four is a gesture that leads nowhere.
class QuickAddShelf extends StatelessWidget {
  const QuickAddShelf({required this.foods, required this.onAdd, super.key});

  final List<Food> foods;
  final void Function(Food) onAdd;

  /// The shelf is always cut into four, however many foods fill it: one food dividing the whole
  /// width made a single tile with a photograph taller than the phone.
  static const _slots = 4;

  @override
  Widget build(BuildContext context) {
    // The tiles divide the width they are given rather than carrying a fixed one: the same four
    // have to sit on a 320 pt phone and on a tablet's sheet.
    return LayoutBuilder(
      builder: (context, constraints) {
        const gaps = AppSpacing.sm * (_slots - 1);
        final tile = (constraints.maxWidth - gaps) / _slots;

        return IntrinsicHeight(
          child: Row(
            // Equal-height tiles: a two-line name must not make one card taller than its
            // neighbours, which is what turns a shelf into a staircase.
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final food in foods) ...[
                if (food != foods.first) const SizedBox(width: AppSpacing.sm),
                SizedBox(
                  width: tile,
                  child: _QuickAddTile(
                    food: food,
                    // The tile's own width, less its padding: nothing can measure through a
                    // `LayoutBuilder`, and equal heights across the shelf need this measurement.
                    imageWidth: tile - AppSpacing.sm * 2,
                    onAdd: () => onAdd(food),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

/// One tile on the shelf, as the reference draws it: the photograph, the name, what it costs per
/// 100 g, and the green `+` at the foot.
class _QuickAddTile extends StatelessWidget {
  const _QuickAddTile({required this.food, required this.imageWidth, required this.onAdd});

  final Food food;
  final double imageWidth;
  final VoidCallback onAdd;

  /// The `+` disc. Decoration — the whole tile adds — so it is not held to the 48 pt minimum.
  static const _disc = 30.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return AppCard(
      onTap: onAdd,
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Column(
        children: [
          FoodImage(
            url: food.imageUrl,
            attribution: food.imageAttribution,
            size: imageWidth,
            height: imageWidth * 0.8,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            food.name,
            // Two lines then an ellipsis: a tile that grows to fit "Amaranth leaves (cooked)"
            // drags the whole shelf down with it.
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            '${food.kcalPer100g.round()} kcal / 100 g',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall,
          ),
          const Spacer(),
          const SizedBox(height: AppSpacing.sm),
          ExcludeSemantics(
            child: Container(
              height: _disc,
              width: _disc,
              decoration: BoxDecoration(color: scheme.primary, shape: BoxShape.circle),
              child: Icon(Icons.add, size: AppSpacing.lg, color: scheme.onPrimary),
            ),
          ),
        ],
      ),
    );
  }
}

/// The diet filter: every food, or the ones that suit one food preference (docs/03 §2).
///
/// A menu rather than chips — the group chips already sit under the heading, and a second row of
/// chips would be a second toolbar. The preferences are the app's OWN vocabulary, the same labels
/// onboarding used (CLAUDE.md rule 4).
class CategoryPill extends StatelessWidget {
  const CategoryPill({required this.selected, required this.onChanged, super.key});

  final FoodPreference? selected;
  final ValueChanged<FoodPreference?> onChanged;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final label = selected?.label(l) ?? l.logFoodsCategoryAll;

    return PopupMenuButton<FoodPreference?>(
      tooltip: l.logFoodsCategory,
      initialValue: selected,
      onSelected: onChanged,
      position: PopupMenuPosition.under,
      itemBuilder: (context) => [
        // Null first: "all" is where the list starts and where a user backs out to.
        PopupMenuItem<FoodPreference?>(child: Text(l.logFoodsCategoryAll)),
        for (final preference in FoodPreference.values)
          PopupMenuItem<FoodPreference?>(value: preference, child: Text(preference.label(l))),
      ],
      child: Container(
        constraints: const BoxConstraints(minHeight: AppSpacing.minTouchTarget),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        decoration: BoxDecoration(
          // Filled once it is doing something: a filter that is ON must not look like one that
          // is off.
          color: selected == null
              ? Colors.transparent
              : scheme.secondaryContainer.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: Border.all(color: scheme.primary.withValues(alpha: 0.4)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelLarge?.copyWith(color: scheme.primary),
              ),
            ),
            Icon(Icons.expand_more, size: AppSpacing.xl, color: scheme.primary),
          ],
        ),
      ),
    );
  }
}

/// The way back to the whole table from a search.
class ViewAllButton extends StatelessWidget {
  const ViewAllButton({required this.label, required this.onTap, super.key});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Material(
      color: scheme.secondaryContainer.withValues(alpha: 0.5),
      borderRadius: BorderRadius.circular(AppRadius.pill),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        child: Container(
          constraints: const BoxConstraints(minHeight: AppSpacing.minTouchTarget),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label, style: theme.textTheme.labelLarge?.copyWith(color: scheme.primary)),
              Icon(Icons.chevron_right, size: AppSpacing.xl, color: scheme.primary),
            ],
          ),
        ),
      ),
    );
  }
}

/// One food: its photograph, its name, kcal and C · P · F per 100 g, and the way to add it.
///
/// A card rather than a `ListTile` — a list of 280 rows on one flat surface is a wall. The whole
/// card adds; the `+` is where the eye goes, not the only place a finger may land.
class FoodRow extends StatelessWidget {
  const FoodRow({required this.food, required this.onAdd, super.key});

  final Food food;
  final VoidCallback onAdd;

  static const _thumb = 72.0;
  static const _thumbHeight = _thumb * 0.8;

  /// Decoration, not a target (the whole card taps).
  static const _addDisc = 40.0;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final p = food.proteinPer100g;
    final c = food.carbPer100g;
    final f = food.fatPer100g;

    return AppCard(
      onTap: onAdd,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.sm,
        AppSpacing.sm,
        AppSpacing.md,
        AppSpacing.sm,
      ),
      child: Row(
        children: [
          // A picture per row, and a placeholder of the same size when there is none — a gap
          // reads as a broken row.
          FoodImage(
            url: food.imageUrl,
            attribution: food.imageAttribution,
            size: _thumb,
            height: _thumbHeight,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  food.name,
                  style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
                Text('${food.kcalPer100g.round()} kcal / 100 g', style: theme.textTheme.bodySmall),
                // Only when the server sent all three: a line with a gap in it reads as a zero.
                if (p != null && c != null && f != null) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Wrap(
                    spacing: AppSpacing.md,
                    runSpacing: AppSpacing.xs,
                    children: [
                      _MacroDot(label: l.logCarbShort, grams: c, color: AppColors.macroCarb),
                      _MacroDot(label: l.logProteinShort, grams: p, color: AppColors.macroProtein),
                      _MacroDot(label: l.logFatShort, grams: f, color: AppColors.macroFat),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          ExcludeSemantics(
            child: Container(
              height: _addDisc,
              width: _addDisc,
              decoration: BoxDecoration(
                color: scheme.secondaryContainer.withValues(alpha: 0.6),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.add, size: AppSpacing.xl, color: scheme.onSecondaryContainer),
            ),
          ),
        ],
      ),
    );
  }
}

/// "● C 28g" — the macro's ring colour, its initial, its grams per 100 g.
class _MacroDot extends StatelessWidget {
  const _MacroDot({required this.label, required this.grams, required this.color});

  final String label;
  final double grams;
  final Color color;

  static const _dot = 8.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: _dot,
          height: _dot,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: AppSpacing.xs),
        Text('$label ${grams.round()}g', style: theme.textTheme.bodySmall),
      ],
    );
  }
}
