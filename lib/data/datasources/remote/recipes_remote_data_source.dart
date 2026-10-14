import 'package:dartz/dartz.dart';
import 'package:dio/dio.dart';
import 'package:health_pro/core/errors/failures.dart';
import 'package:health_pro/core/network/error_mapper.dart';
import 'package:health_pro/domain/entities/recipe.dart';

/// `GET /recipes` and `POST /recipes/{id}/log` (D-263).
class RecipesRemoteDataSource {
  const RecipesRemoteDataSource(this._dio);

  final Dio _dio;

  Future<Either<Failure, List<Recipe>>> list({String? slot}) async {
    try {
      final res = await _dio.get<List<dynamic>>(
        '/recipes',
        // A meal name only — no health data in the query (api rule 6). The server applies the
        // reader's own food preference itself.
        queryParameters: {if (slot != null) 'slot': slot},
      );
      return Right(
        (res.data ?? const []).map((e) => recipeFromJson(e as Map<String, dynamic>)).toList(),
      );
    } on DioException catch (e) {
      return Left(mapDioError(e));
    }
  }

  Future<Either<Failure, Unit>> log({
    required String id,
    required String slot,
    required double servings,
  }) async {
    try {
      await _dio.post<void>('/recipes/$id/log', data: {'slot': slot, 'servings': servings});
      return const Right(unit);
    } on DioException catch (e) {
      return Left(mapDioError(e));
    }
  }
}

/// The server's `RecipeView`, snake_case, into the entity.
Recipe recipeFromJson(Map<String, dynamic> json) {
  List<String> strings(String key) =>
      (json[key] as List? ?? const []).map((e) => e.toString()).toList();
  double number(Map<String, dynamic> m, String key) => (m[key] as num?)?.toDouble() ?? 0;
  final serving = json['per_serving'] as Map<String, dynamic>? ?? const {};

  return Recipe(
    id: json['id'] as String,
    name: json['name'] as String,
    nameHi: json['name_hi'] as String?,
    description: json['description'] as String? ?? '',
    steps: strings('steps'),
    slots: strings('slots'),
    servings: (json['servings'] as num?)?.toInt() ?? 1,
    suitableFor: strings('suitable_for'),
    allergens: strings('allergens'),
    perServing: RecipeNutrition(
      grams: number(serving, 'grams'),
      kcal: number(serving, 'kcal'),
      proteinG: number(serving, 'protein_g'),
      carbG: number(serving, 'carb_g'),
      fatG: number(serving, 'fat_g'),
      fibreG: number(serving, 'fibre_g'),
    ),
    ingredients: (json['ingredients'] as List? ?? const []).map((e) {
      final i = e as Map<String, dynamic>;
      return RecipeIngredient(
        foodId: i['food_id'] as String,
        name: i['name'] as String,
        nameHi: i['name_hi'] as String?,
        grams: number(i, 'grams'),
      );
    }).toList(),
  );
}
