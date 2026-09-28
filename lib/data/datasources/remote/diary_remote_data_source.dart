import 'package:dartz/dartz.dart';
import 'package:dio/dio.dart';
import 'package:health_pro/core/errors/failures.dart';
import 'package:health_pro/core/network/error_mapper.dart';
import 'package:health_pro/domain/entities/food.dart';
import 'package:health_pro/domain/entities/health_metric.dart';

/// docs/09 §5 over dio.
class DiaryRemoteDataSource {
  const DiaryRemoteDataSource(this._dio);

  final Dio _dio;

  Future<Either<Failure, List<Food>>> searchFoods(
    String query, {
    int limit = 20,
    int offset = 0,
    String? suitableFor,
    List<String>? groups,
  }) async {
    try {
      final res = await _dio.get<List<dynamic>>(
        '/foods',
        queryParameters: {
          'q': query,
          'limit': limit,
          'offset': offset,
          // Omitted rather than sent empty: the server rejects a preference it does not know, and
          // an empty string is not "no filter" to it.
          if (suitableFor != null) 'suitableFor': suitableFor,
          if (groups != null && groups.isNotEmpty) 'group': groups.join(','),
        },
      );
      // Image paths are relative — resolved here, where the base URL already lives (D-83).
      final base = _dio.options.baseUrl;
      return Right(
        (res.data ?? [])
            .map((f) => Food.fromJson(f as Map<String, dynamic>).absolute(base))
            .toList(),
      );
    } on DioException catch (e) {
      return Left(mapDioError(e));
    }
  }

  /// The server resolves the diary day and scales the nutrition — the client sends only what the
  /// user chose (CLAUDE.md rules 2 and 8).
  Future<Either<Failure, LogEntry>> logFood({
    required String slot,
    required String foodId,
    String? measure,
    double? measureCount,
    double? quantityG,
    String? source,
  }) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        '/logs/food',
        data: {
          'slot': slot,
          'food_id': foodId,
          if (measure != null) 'measure': measure,
          if (measureCount != null) 'measure_count': measureCount,
          if (quantityG != null) 'quantity_g': quantityG,
          if (source != null) 'source': source,
        },
      );
      return Right(LogEntry.fromJson(res.data!, imageBase: _dio.options.baseUrl));
    } on DioException catch (e) {
      return Left(mapDioError(e));
    }
  }

  /// A POST, not a GET: the body names a food and a portion, and the API keeps health data out of
  /// query strings.
  Future<Either<Failure, NutritionPreview>> previewFood({
    required String foodId,
    String? measure,
    double? measureCount,
    double? quantityG,
  }) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        '/logs/food/preview',
        data: {
          'food_id': foodId,
          if (measure != null) 'measure': measure,
          if (measureCount != null) 'measure_count': measureCount,
          if (quantityG != null) 'quantity_g': quantityG,
        },
      );
      return Right(NutritionPreview.fromJson(res.data ?? const {}));
    } on DioException catch (e) {
      return Left(mapDioError(e));
    }
  }

  Future<Either<Failure, DiaryDay>> day({String? date}) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        '/logs/day',
        // Omitted for today. The server resolves the 04:00 IST boundary either way (rule 8) —
        // this only says WHICH day is being read, never when a day starts.
        queryParameters: {if (date != null) 'date': date},
      );
      // Photo paths are relative — resolved here, where the base URL already lives (D-83).
      return Right(DiaryDay.fromJson(res.data ?? const {}, imageBase: _dio.options.baseUrl));
    } on DioException catch (e) {
      return Left(mapDioError(e));
    }
  }

  Future<Either<Failure, List<DiaryWindow>>> windows(int days) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        '/logs/windows',
        queryParameters: {'days': days},
      );
      final rows = (res.data?['windows'] as List<dynamic>?) ?? const [];
      return Right([for (final row in rows) DiaryWindow.fromJson(row as Map<String, dynamic>)]);
    } on DioException catch (e) {
      return Left(mapDioError(e));
    }
  }

  Future<Either<Failure, Unit>> remove(String id) async {
    try {
      await _dio.delete<void>('/logs/food/$id');
      return const Right(unit);
    } on DioException catch (e) {
      return Left(mapDioError(e));
    }
  }
}
