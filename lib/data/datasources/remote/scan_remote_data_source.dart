import 'package:dartz/dartz.dart';
import 'package:dio/dio.dart';
import 'package:health_pro/core/errors/failures.dart';
import 'package:health_pro/core/network/error_mapper.dart';
import 'package:health_pro/domain/entities/food.dart';
import 'package:health_pro/domain/entities/food_scan.dart';

/// D-238/D-240 over dio.
class ScanRemoteDataSource {
  const ScanRemoteDataSource(this._dio);

  final Dio _dio;

  /// Estimating a plate is a model call, slower than any other request — but still bounded, so the
  /// analysing screen always ends in an answer or a retry (rule 6: no infinite spinners).
  static const _scanTimeout = Duration(seconds: 45);

  Future<Either<Failure, ScanStatus>> status() async {
    try {
      final res = await _dio.get<Map<String, dynamic>>('/foods/scan/status');
      return Right(ScanStatus.fromJson(res.data ?? const {}));
    } on DioException catch (e) {
      return Left(mapDioError(e));
    }
  }

  Future<Either<Failure, ScanEstimate>> scan(
    String filePath,
    String fileName, {
    required bool adWatched,
  }) async {
    try {
      final form = FormData.fromMap({
        'image': await MultipartFile.fromFile(filePath, filename: fileName),
        'ad_watched': adWatched ? 'true' : 'false',
      });
      final res = await _dio.post<Map<String, dynamic>>(
        '/foods/scan',
        data: form,
        options: Options(sendTimeout: _scanTimeout, receiveTimeout: _scanTimeout),
      );
      return Right(ScanEstimate.fromJson(res.data ?? const {}));
    } on DioException catch (e) {
      return Left(mapDioError(e));
    }
  }

  Future<Either<Failure, LogEntry>> confirm(
    int scanId, {
    required String slot,
    required List<int> keep,
  }) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        '/foods/scan/$scanId/log',
        data: {'slot': slot, 'keep': keep},
      );
      return Right(LogEntry.fromJson(res.data ?? const {}, imageBase: _dio.options.baseUrl));
    } on DioException catch (e) {
      return Left(mapDioError(e));
    }
  }

  Future<Either<Failure, Unit>> discard(int scanId) async {
    try {
      await _dio.delete<void>('/foods/scan/$scanId');
      return const Right(unit);
    } on DioException catch (e) {
      return Left(mapDioError(e));
    }
  }
}
