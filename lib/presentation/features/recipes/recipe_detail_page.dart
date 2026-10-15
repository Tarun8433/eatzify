import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:health_pro/core/theme/app_spacing.dart';
import 'package:health_pro/core/widgets/app_card.dart';
import 'package:health_pro/core/widgets/app_sheet.dart';
import 'package:health_pro/domain/entities/onboarding_enums.dart';
import 'package:health_pro/domain/entities/recipe.dart';
import 'package:health_pro/presentation/features/home/home_controller.dart';
import 'package:health_pro/presentation/features/onboarding/enum_labels.dart';
import 'package:health_pro/presentation/features/recipes/recipes_controller.dart';
import 'package:health_pro/presentation/features/recipes/recipes_page.dart' show recipeSlots;
import 'package:health_pro/presentation/l10n/app_localizations.dart';
import 'package:health_pro/presentation/shell/food_log/portion_sheet.dart' show slotLabel;

/// D-263: one recipe — what a serving gives, what goes in it, how it is made, and "Log this".
/// Every figure is the server's; the page only lays them out.
class RecipeDetailPage extends StatelessWidget {
  const RecipeDetailPage({required this.recipe, super.key});

  final Recipe recipe;

  /// Shares the list's controller: it is already registered while the list is open.
  static Future<void>? open(Recipe recipe) => Get.to<void>(() => RecipeDetailPage(recipe: recipe));

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final hindi = Localizations.localeOf(context).languageCode == 'hi';
    final n = recipe.perServing;
    final allergens = recipe.allergens
        .map((wire) => FoodAllergy.values.where((a) => a.wire == wire).firstOrNull?.label(l))
        .nonNulls
        .join(', ');

    return Scaffold(
      appBar: AppBar(title: Text(hindi && recipe.nameHi != null ? recipe.nameHi! : recipe.name)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.screenH,
          AppSpacing.sm,
          AppSpacing.screenH,
          AppSpacing.xxl,
        ),
        children: [
          if (recipe.description.isNotEmpty) ...[
            Text(recipe.description, style: theme.textTheme.bodyLarge),
            const SizedBox(height: AppSpacing.md),
          ],
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l.recipePerServing, style: theme.textTheme.bodySmall),
                Text(
                  l.recipeKcal(n.kcal.round()),
                  style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  l.recipeMacros(n.proteinG, n.carbG, n.fatG),
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(l.recipeServings(recipe.servings), style: theme.textTheme.bodySmall),
              ],
            ),
          ),
          // Stated plainly, not as a warning: the person knows their own allergies (docs/05 §6).
          if (allergens.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            HintCard(dense: true, icon: Icons.info_outline, text: l.recipeContains(allergens)),
          ],
          const SizedBox(height: AppSpacing.lg),
          _Heading(l.recipeIngredients),
          for (final i in recipe.ingredients)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      hindi && i.nameHi != null ? i.nameHi! : i.name,
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                  Text(l.recipeGrams(i.grams), style: theme.textTheme.bodyMedium),
                ],
              ),
            ),
          if (recipe.steps.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.lg),
            _Heading(l.recipeMethod),
            for (final (index, step) in recipe.steps.indexed)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: AppSpacing.xl,
                      child: Text('${index + 1}.', style: theme.textTheme.bodyMedium),
                    ),
                    Expanded(child: Text(step, style: theme.textTheme.bodyMedium)),
                  ],
                ),
              ),
          ],
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.screenH),
          child: FilledButton.icon(
            onPressed: () => _LogSheet.show(context, recipe),
            icon: const Icon(Icons.add),
            label: Text(l.recipeLog),
          ),
        ),
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.xs),
    child: Text(
      text,
      style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
    ),
  );
}

/// Which meal, how many servings, then one call. The meal starts on the recipe's first slot; the
/// person picks — the app never decides what they ate (docs/05 §6).
class _LogSheet extends StatefulWidget {
  const _LogSheet({required this.recipe});

  final Recipe recipe;

  static Future<void> show(BuildContext context, Recipe recipe) => showAppSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _LogSheet(recipe: recipe),
  );

  @override
  State<_LogSheet> createState() => _LogSheetState();
}

class _LogSheetState extends State<_LogSheet> {
  /// Servings people actually eat; whole numbers past two would rarely be one person's meal.
  static const _servingChoices = [0.5, 1.0, 1.5, 2.0];

  late String _slot = widget.recipe.slots.firstOrNull ?? recipeSlots.first;
  double _servings = 1;
  String? _error;

  Future<void> _log() async {
    final c = Get.find<RecipesController>();
    final failure = await c.log(widget.recipe, slot: _slot, servings: _servings);
    if (!mounted) return;
    if (failure != null) {
      setState(() => _error = failure);
      return;
    }
    // Home shows the diary these entries just joined.
    if (Get.isRegistered<HomeController>()) await Get.find<HomeController>().load();
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final logged = AppLocalizations.of(context).recipeLogged;
    Navigator.of(context).pop();
    messenger.showSnackBar(SnackBar(content: Text(logged)));
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final c = Get.find<RecipesController>();

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.screenH,
          0,
          AppSpacing.screenH,
          AppSpacing.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l.recipeLogMeal, style: theme.textTheme.titleMedium),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                for (final slot in recipeSlots)
                  ChoiceChip(
                    label: Text(slotLabel(l, slot)),
                    selected: _slot == slot,
                    onSelected: (_) => setState(() => _slot = slot),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(l.recipeLogServings, style: theme.textTheme.titleMedium),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              children: [
                for (final s in _servingChoices)
                  ChoiceChip(
                    label: Text(s == s.roundToDouble() ? '${s.toInt()}' : '$s'),
                    selected: _servings == s,
                    onSelected: (_) => setState(() => _servings = s),
                  ),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.md),
              // The server's words (rule 7).
              Text(
                _error!,
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
              ),
            ],
            const SizedBox(height: AppSpacing.lg),
            Obx(
              () =>
                  FilledButton(onPressed: c.logging.value ? null : _log, child: Text(l.recipeLog)),
            ),
          ],
        ),
      ),
    );
  }
}
