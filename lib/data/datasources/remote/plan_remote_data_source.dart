import 'package:dartz/dartz.dart';
import 'package:dio/dio.dart';
import 'package:health_pro/core/errors/failures.dart';
import 'package:health_pro/core/network/error_mapper.dart';
import 'package:health_pro/domain/entities/plan.dart';

/// docs/09 §4.2 over dio.
class PlanRemoteDataSource {
  const PlanRemoteDataSource(this._dio);

  final Dio _dio;

  /// `GET /plans/current`. Null on the right means no plan yet — an Empty state, not a failure.
  Future<Either<Failure, Plan?>> current() async {
    try {
      final res = await _dio.get<Map<String, dynamic>>('/plans/current');
      final data = res.data;
      return Right(data == null ? null : Plan.fromJson(data));
    } on DioException catch (e) {
      return Left(mapDioError(e));
    }
  }

  /// `GET /plans/options` (D-82). A list, never null: no eligible food is an empty list, which the
  /// UI says in words rather than showing an error.
  Future<Either<Failure, Map<String, List<FoodOption>>>> options() async {
    try {
      final res = await _dio.get<Map<String, dynamic>>('/plans/options');
      // Image paths arrive relative — resolved here, where the base URL already lives (D-83).
      // Left relative they reach `CachedNetworkImage` as "/food-images/x.jpg", which is not a URL
      // it can fetch, so every card silently fell back to its placeholder.
      final base = _dio.options.baseUrl;
      return Right({
        for (final entry in (res.data ?? const <String, dynamic>{}).entries)
          entry.key: (entry.value as List? ?? [])
              .map((e) => FoodOption.fromJson(e as Map<String, dynamic>).absolute(base))
              .toList(),
      });
    } on DioException catch (e) {
      return Left(mapDioError(e));
    }
  }

  /// `POST /plans/generate`. Inputs come from the server-side profile — the body carries only a
  /// reason, so the client cannot influence what the engine is given.
  ///
  /// A blocking gate arrives as 422 `PLAN_GATE_BLOCKED` carrying the docs/05 §7 referral copy,
  /// which `mapDioError` surfaces as the failure's `userMessage` (rule 7).
  Future<Either<Failure, Unit>> generate({String reason = 'user_request'}) async {
    try {
      await _dio.post<Map<String, dynamic>>('/plans/generate', data: {'regenerate_reason': reason});
      return const Right(unit);
    } on DioException catch (e) {
      return Left(mapDioError(e));
    }
  }
}
