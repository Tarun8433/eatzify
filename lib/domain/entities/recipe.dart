/// A dish made of foods (D-263). Every figure is the server's, derived from the foods in it — the
/// app shows them and never adds anything up itself (rule 2).
class Recipe {
  const Recipe({
    required this.id,
    required this.name,
    required this.nameHi,
    required this.description,
    required this.steps,
    required this.slots,
    required this.servings,
    required this.suitableFor,
    required this.allergens,
    required this.perServing,
    required this.ingredients,
  });

  final String id;
  final String name;
  final String? nameHi;
  final String description;
  final List<String> steps;

  /// Meal slot wire values (`breakfast`, `lunch`…) — labelled through l10n (rule 4).
  final List<String> slots;

  /// How many servings the ingredient grams make.
  final int servings;

  /// Food preference wire values (`veg`, `vegan`…).
  final List<String> suitableFor;

  /// Allergen wire values (`milk`, `wheat_gluten`…).
  final List<String> allergens;

  final RecipeNutrition perServing;
  final List<RecipeIngredient> ingredients;
}

/// One serving's nutrition, as the server worked it out.
class RecipeNutrition {
  const RecipeNutrition({
    required this.grams,
    required this.kcal,
    required this.proteinG,
    required this.carbG,
    required this.fatG,
    required this.fibreG,
  });

  final double grams;
  final double kcal;
  final double proteinG;
  final double carbG;
  final double fatG;
  final double fibreG;
}

/// One food, in grams for the WHOLE recipe.
class RecipeIngredient {
  const RecipeIngredient({
    required this.foodId,
    required this.name,
    required this.nameHi,
    required this.grams,
  });

  final String foodId;
  final String name;
  final String? nameHi;
  final double grams;
}
