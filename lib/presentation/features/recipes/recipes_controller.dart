import 'package:get/get.dart';
import 'package:health_pro/core/widgets/view_state.dart';
import 'package:health_pro/domain/entities/recipe.dart';
import 'package:health_pro/domain/repositories/recipe_repository.dart';

/// D-263: the recipe list behind the four states (rule 6), one meal filter, and logging.
class RecipesController extends GetxController {
  RecipesController({required this.recipes});

  final RecipeRepository recipes;

  final state = Rx<ViewState<List<Recipe>>>(const Loading());

  /// The meal chip; null is every meal.
  final slot = RxnString();

  /// True while a log is in flight — the button is disabled, so a double tap logs once.
  final logging = false.obs;

  @override
  void onInit() {
    super.onInit();
    load();
  }

  Future<void> load() async {
    state.value = const Loading();
    final result = await recipes.list(slot: slot.value);
    state.value = result.fold(Failed.new, (list) => list.isEmpty ? const Empty() : Ready(list));
  }

  Future<void> filter(String? value) async {
    if (slot.value == value) return;
    slot.value = value;
    await load();
  }

  /// The server's `user_message` on failure (rule 7), null on success.
  Future<String?> log(Recipe recipe, {required String slot, required double servings}) async {
    if (logging.value) return null;
    logging.value = true;
    final result = await recipes.log(id: recipe.id, slot: slot, servings: servings);
    logging.value = false;
    return result.fold((f) => f.userMessage, (_) => null);
  }
}
