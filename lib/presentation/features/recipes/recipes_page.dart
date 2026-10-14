import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:health_pro/core/theme/app_spacing.dart';
import 'package:health_pro/core/widgets/app_card.dart';
import 'package:health_pro/core/widgets/state_views.dart';
import 'package:health_pro/core/widgets/view_state.dart';
import 'package:health_pro/domain/entities/recipe.dart';
import 'package:health_pro/domain/repositories/recipe_repository.dart';
import 'package:health_pro/presentation/features/recipes/recipe_detail_page.dart';
import 'package:health_pro/presentation/features/recipes/recipes_controller.dart';
import 'package:health_pro/presentation/l10n/app_localizations.dart';
import 'package:health_pro/presentation/shell/food_log/portion_sheet.dart' show slotLabel;

/// The meals the chips offer, in the order a day runs (docs/09 §5).
const recipeSlots = ['breakfast', 'mid_morning', 'lunch', 'snack', 'evening', 'dinner', 'bedtime'];

/// D-263: published recipes, already narrowed by the server to the reader's food preference.
/// Pushed from the Plan tab — not a tab of its own (rule 1).
class RecipesPage extends StatelessWidget {
  const RecipesPage({super.key});

  static Future<void>? open() => Get.to<void>(
    () => const RecipesPage(),
    binding: BindingsBuilder<void>(() {
      Get.lazyPut(() => RecipesController(recipes: Get.find<RecipeRepository>()));
    }),
  );

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = Get.find<RecipesController>();

    return Scaffold(
      appBar: AppBar(title: Text(l.recipesTitle)),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SlotChips(controller: c),
          Expanded(
            child: Obx(
              () => switch (c.state.value) {
                Loading<List<Recipe>>() => const LoadingView(),
                Failed<List<Recipe>>(:final failure) => FailedView(
                  failure: failure,
                  onRetry: c.load,
                  retryLabel: l.accountRetry,
                ),
                Empty<List<Recipe>>() => EmptyView(
                  title: l.recipesEmptyTitle,
                  body: l.recipesEmptyBody,
                  // With a meal chosen, the one action is to widen it again.
                  actionLabel: c.slot.value == null ? null : l.recipesShowAll,
                  onAction: c.slot.value == null ? null : () => c.filter(null),
                ),
                Ready<List<Recipe>>(:final data) => RefreshIndicator(
                  onRefresh: c.load,
                  child: ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.screenH,
                      AppSpacing.sm,
                      AppSpacing.screenH,
                      AppSpacing.xxl,
                    ),
                    itemCount: data.length,
                    separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
                    itemBuilder: (_, i) => _RecipeTile(recipe: data[i]),
                  ),
                ),
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _SlotChips extends StatelessWidget {
  const _SlotChips({required this.controller});

  final RecipesController controller;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);

    return SizedBox(
      height: AppSpacing.minTouchTarget + AppSpacing.md,
      child: Obx(
        () => ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.screenH,
            vertical: AppSpacing.xs,
          ),
          children: [
            for (final slot in [null, ...recipeSlots]) ...[
              ChoiceChip(
                label: Text(slot == null ? l.recipesAllMeals : slotLabel(l, slot)),
                selected: controller.slot.value == slot,
                onSelected: (_) => controller.filter(slot),
              ),
              const SizedBox(width: AppSpacing.sm),
            ],
          ],
        ),
      ),
    );
  }
}

class _RecipeTile extends StatelessWidget {
  const _RecipeTile({required this.recipe});

  final Recipe recipe;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final hindi = Localizations.localeOf(context).languageCode == 'hi';
    final name = hindi && recipe.nameHi != null ? recipe.nameHi! : recipe.name;

    return AppCard(
      onTap: () => RecipeDetailPage.open(recipe),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
                if (recipe.description.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(recipe.description, style: theme.textTheme.bodySmall),
                ],
                const SizedBox(height: AppSpacing.xs),
                Text(
                  '${l.recipePerServing}: ${l.recipeKcal(recipe.perServing.kcal.round())}',
                  style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right),
        ],
      ),
    );
  }
}
