import 'package:dartz/dartz.dart';
import 'package:dio/dio.dart';
import 'package:health_pro/core/errors/failures.dart';
import 'package:health_pro/core/network/error_mapper.dart';

typedef Json = Map<String, dynamic>;

/// `/gym` over dio (ADR-013). Returns the server's JSON: the repository parses it, and caches the
/// overview and the exercise list as the server sent them.
class GymRemoteDataSource {
  const GymRemoteDataSource(this._dio);

  final Dio _dio;

  Future<Either<Failure, Json>> overview() => _get('/gym');

  Future<Either<Failure, Json>> exercises() => _get('/gym/exercises');

  Future<Either<Failure, Json>> exercise(String id) =>
      _get('/gym/exercises/${Uri.encodeComponent(id)}');

  Future<Either<Failure, Json>> progress(String id) =>
      _get('/gym/exercises/${Uri.encodeComponent(id)}/progress');

  Future<Either<Failure, Json>> createExercise(Json body) => _send('POST', '/gym/exercises', body);

  Future<Either<Failure, Json>> updateExercise(String id, Json body) =>
      _send('PATCH', '/gym/exercises/${Uri.encodeComponent(id)}', body);

  Future<Either<Failure, Unit>> deleteExercise(String id) =>
      _delete('/gym/exercises/${Uri.encodeComponent(id)}');

  Future<Either<Failure, Json>> createRoutine(Json body) => _send('POST', '/gym/routines', body);

  Future<Either<Failure, Json>> updateRoutine(int id, Json body) =>
      _send('PUT', '/gym/routines/$id', body);

  Future<Either<Failure, Unit>> deleteRoutine(int id) => _delete('/gym/routines/$id');

  Future<Either<Failure, Json>> starter() => _send('POST', '/gym/routines/starter', null);

  Future<Either<Failure, Json>> schedule(Json body) => _send('PUT', '/gym/schedule', body);

  Future<Either<Failure, Json>> day(Json body) => _send('POST', '/gym/schedule/day', body);

  Future<Either<Failure, Json>> settings(Json body) => _send('PATCH', '/gym/settings', body);

  Future<Either<Failure, Json>> saveWorkout(Json body) => _send('POST', '/gym/workouts', body);

  Future<Either<Failure, Json>> history({String? before}) =>
      _get('/gym/workouts', query: {'before': ?before});

  Future<Either<Failure, Json>> workout(String id) => _get('/gym/workouts/$id');

  Future<Either<Failure, Unit>> deleteWorkout(String id) => _delete('/gym/workouts/$id');

  Future<Either<Failure, Json>> stats({String? muscleWindow, String? effortWindow, bool? hard}) =>
      _get(
        '/gym/stats',
        query: {
          'muscle_window': ?muscleWindow,
          'effort_window': ?effortWindow,
          'hard': ?hard?.toString(),
        },
      );

  Future<Either<Failure, Json>> calendar(String month) =>
      _get('/gym/calendar', query: {'month': month});

  Future<Either<Failure, Json>> _get(String path, {Map<String, String>? query}) async {
    try {
      final res = await _dio.get<Json>(path, queryParameters: query);
      return Right(res.data ?? const {});
    } on DioException catch (e) {
      return Left(mapDioError(e));
    }
  }

  Future<Either<Failure, Json>> _send(String method, String path, Json? body) async {
    try {
      final res = await _dio.request<Json>(
        path,
        data: body,
        options: Options(method: method),
      );
      return Right(res.data ?? const {});
    } on DioException catch (e) {
      return Left(mapDioError(e));
    }
  }

  Future<Either<Failure, Unit>> _delete(String path) async {
    try {
      await _dio.delete<void>(path);
      return const Right(unit);
    } on DioException catch (e) {
      return Left(mapDioError(e));
    }
  }
}
