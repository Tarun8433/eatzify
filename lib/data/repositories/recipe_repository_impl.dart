import 'package:dartz/dartz.dart';
import 'package:health_pro/core/errors/failures.dart';
import 'package:health_pro/data/datasources/remote/recipes_remote_data_source.dart';
import 'package:health_pro/domain/entities/recipe.dart';
import 'package:health_pro/domain/repositories/recipe_repository.dart';

class RecipeRepositoryImpl implements RecipeRepository {
  const RecipeRepositoryImpl(this._remote);

  final RecipesRemoteDataSource _remote;

  @override
  Future<Either<Failure, List<Recipe>>> list({String? slot}) => _remote.list(slot: slot);

  @override
  Future<Either<Failure, Unit>> log({
    required String id,
    required String slot,
    required double servings,
  }) => _remote.log(id: id, slot: slot, servings: servings);
}
