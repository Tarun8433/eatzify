import 'package:flutter/material.dart';
import 'package:health_pro/core/theme/app_spacing.dart';
import 'package:health_pro/core/widgets/food_image.dart';
import 'package:health_pro/domain/entities/food.dart';
import 'package:health_pro/presentation/l10n/app_localizations.dart';
import 'package:health_pro/presentation/shell/food_log/nutrition_card.dart';

/// docs/09 §5 slots, in the order a day runs.
const mealSlots = ['breakfast', 'mid_morning', 'lunch', 'snack', 'evening', 'dinner', 'bedtime'];

/// What the user chose: the meal, and how much. A null `measure` means `count` is grams.
typedef PortionChoice = ({String slot, String? measure, double count});

/// CLAUDE.md rule 4: a slot is an enum on the wire and l10n on screen.
String slotLabel(AppLocalizations l, String slot) => switch (slot) {
  'breakfast' => l.slotBreakfast,
  'mid_morning' => l.slotMidMorning,
  'lunch' => l.slotLunch,
  'snack' => l.slotSnack,
  'evening' => l.slotEvening,
  'dinner' => l.slotDinner,
  _ => l.slotBedtime,
};

/// The meal a log most likely belongs to at [hour] — only where the chips START, the user picks.
/// The diary DAY is still the server's (rule 8); this never decides which day an entry lands on.
String slotForHour(int hour) => switch (hour) {
  >= 5 && < 10 => 'breakfast',
  >= 10 && < 12 => 'mid_morning',
  >= 12 && < 15 => 'lunch',
  >= 15 && < 17 => 'snack',
  >= 17 && < 19 => 'evening',
  >= 19 && < 22 => 'dinner',
  _ => 'bedtime',
};

/// A food with no household measure is logged in grams, from a sensible 100 g in steps of 10 —
/// the old sheet started at "1 g" and stepped by half a gram.
const _gramsStart = 100.0;
const _gramsStep = 10.0;
const _measureStep = 0.5;

/// Starting count for a portion: one of the default measure, or 100 g.
double initialCount(Food food) => food.defaultMeasure == null ? _gramsStart : 1;

/// The meal chips, the measure chips, the stepper and the nutrition they add up to. Controlled:
/// the owner holds the choice, so the add sheet and the scan sheet share one editor.
class PortionEditor extends StatelessWidget {
  const PortionEditor({
    required this.food,
    required this.slot,
    required this.measure,
    required this.count,
    required this.onChanged,
    super.key,
  });

  final Food food;
  final String slot;
  final HouseholdMeasure? measure;
  final double count;
  final void Function({String? slot, HouseholdMeasure? measure, double? count}) onChanged;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final inGrams = measure == null;
    final step = inGrams ? _gramsStep : _measureStep;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MealChips(
          slot: slot,
          onChanged: (s) => onChanged(slot: s),
        ),
        const SizedBox(height: AppSpacing.lg),
        Text(l.logHowMuch, style: theme.textTheme.labelLarge),
        const SizedBox(height: AppSpacing.xs),
        if (food.measures.isNotEmpty)
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            children: [
              for (final m in food.measures)
                ChoiceChip(
                  label: Text('${m.label} · ${m.grams.round()} g'),
                  selected: measure?.label == m.label,
                  onSelected: (_) => onChanged(measure: m),
                ),
            ],
          ),
        const SizedBox(height: AppSpacing.sm),
        Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(AppRadius.pill),
          ),
          child: Row(
            children: [
              IconButton(
                // An icon-only button announces as just "button" without this.
                tooltip: l.logDecrease,
                onPressed: count > step ? () => onChanged(count: count - step) : null,
                icon: const Icon(Icons.remove),
              ),
              Expanded(
                child: Text(
                  inGrams ? '${count.round()} g' : '${_count(count)} × ${measure!.label}',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              IconButton(
                tooltip: l.logIncrease,
                onPressed: () => onChanged(count: count + step),
                icon: const Icon(Icons.add),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        NutritionCard(food: food, measure: measure, count: count),
      ],
    );
  }

  /// "2" rather than "2.0"; "1.5" stays.
  static String _count(double c) => c == c.roundToDouble() ? '${c.round()}' : '$c';
}

/// Which meal an entry goes to — the add sheet and the scan sheet ask the same way.
class MealChips extends StatelessWidget {
  const MealChips({required this.slot, required this.onChanged, super.key});

  final String slot;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l.logSlot, style: theme.textTheme.labelLarge),
        const SizedBox(height: AppSpacing.xs),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.xs,
          children: [
            for (final s in mealSlots)
              ChoiceChip(
                label: Text(slotLabel(l, s)),
                selected: slot == s,
                onSelected: (_) => onChanged(s),
              ),
          ],
        ),
      ],
    );
  }
}

/// The add sheet: the food, then the meal and portion, then what that portion gives, then add.
class PortionSheet extends StatefulWidget {
  const PortionSheet({required this.food, super.key});

  final Food food;

  /// Opens the sheet; resolves to the choice, or null if dismissed.
  static Future<PortionChoice?> show(BuildContext context, Food food) =>
      showModalBottomSheet<PortionChoice>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        showDragHandle: true,
        builder: (_) => PortionSheet(food: food),
      );

  @override
  State<PortionSheet> createState() => _PortionSheetState();
}

class _PortionSheetState extends State<PortionSheet> {
  late String _slot = slotForHour(DateTime.now().hour);
  late HouseholdMeasure? _measure = widget.food.defaultMeasure;
  late double _count = initialCount(widget.food);

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        MediaQuery.of(context).viewInsets.bottom + AppSpacing.xl,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FoodHeader(food: widget.food),
          const SizedBox(height: AppSpacing.lg),
          PortionEditor(
            food: widget.food,
            slot: _slot,
            measure: _measure,
            count: _count,
            onChanged: ({slot, measure, count}) => setState(() {
              if (slot != null) _slot = slot;
              if (measure != null && measure.label != _measure?.label) {
                _measure = measure;
                _count = 1;
              }
              if (count != null) _count = count;
            }),
          ),
          const SizedBox(height: AppSpacing.lg),
          FilledButton(
            onPressed: () => Navigator.of(
              context,
            ).pop<PortionChoice>((slot: _slot, measure: _measure?.label, count: _count)),
            child: Text(l.logAddTo(slotLabel(l, _slot))),
          ),
        ],
      ),
    );
  }
}

/// The food's photograph (credit on long-press, D-83), its name and its per-100 g energy.
class FoodHeader extends StatelessWidget {
  const FoodHeader({required this.food, super.key});

  final Food food;

  static const _photo = 72.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      children: [
        FoodImage(url: food.imageUrl, attribution: food.imageAttribution, size: _photo),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                food.name,
                style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
              Text('${food.kcalPer100g.round()} kcal / 100 g', style: theme.textTheme.bodySmall),
            ],
          ),
        ),
      ],
    );
  }
}
