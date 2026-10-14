import 'package:dartz/dartz.dart';
import 'package:health_pro/core/errors/failures.dart';
import 'package:health_pro/domain/entities/recipe.dart';

/// D-263: the published recipes, narrowed by the server to the reader's own food preference.
abstract class RecipeRepository {
  /// [slot] narrows to one meal; null is every meal.
  Future<Either<Failure, List<Recipe>>> list({String? slot});

  /// Logs [servings] of a recipe into [slot]: the server writes one diary entry per ingredient on
  /// the server's own diary day (rule 8).
  Future<Either<Failure, Unit>> log({
    required String id,
    required String slot,
    required double servings,
  });
}
