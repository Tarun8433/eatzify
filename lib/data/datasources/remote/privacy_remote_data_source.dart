import 'package:dartz/dartz.dart';
import 'package:dio/dio.dart';
import 'package:health_pro/core/errors/failures.dart';
import 'package:health_pro/core/network/error_mapper.dart';
import 'package:health_pro/domain/entities/privacy.dart';

/// `/privacy` (docs/09 + docs/13 §9).
class PrivacyRemoteDataSource {
  const PrivacyRemoteDataSource(this._dio);

  final Dio _dio;

  Future<Either<Failure, PrivacyState>> load() async {
    try {
      // Two calls, one screen. They are separate endpoints because consents change constantly and
      // a request is made once in a lifetime.
      final results = await Future.wait([
        _dio.get<List<dynamic>>('/privacy/consents'),
        _dio.get<List<dynamic>>('/privacy/requests'),
      ]);

      return Right((
        consents: [
          for (final row in results[0].data ?? const [])
            ConsentItem.fromJson(row as Map<String, dynamic>),
        ],
        requests: [
          for (final row in results[1].data ?? const [])
            PrivacyRequest.fromJson(row as Map<String, dynamic>),
        ],
      ));
    } on DioException catch (e) {
      return Left(mapDioError(e));
    }
  }

  Future<Either<Failure, List<ConsentItem>>> setConsent(
    String type, {
    required bool granted,
  }) async {
    try {
      final res = await _dio.post<List<dynamic>>(
        '/privacy/consents',
        data: {'type': type, 'granted': granted},
      );
      return Right([
        for (final row in res.data ?? const []) ConsentItem.fromJson(row as Map<String, dynamic>),
      ]);
    } on DioException catch (e) {
      return Left(mapDioError(e));
    }
  }

  Future<Either<Failure, PrivacyRequest>> requestExport() async {
    try {
      final res = await _dio.post<Map<String, dynamic>>('/privacy/export');
      return Right(PrivacyRequest.fromJson(res.data ?? const {}));
    } on DioException catch (e) {
      return Left(mapDioError(e));
    }
  }

  Future<Either<Failure, Map<String, dynamic>>> exportBundle(String requestId) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>('/privacy/export/$requestId');
      return Right(res.data ?? const {});
    } on DioException catch (e) {
      return Left(mapDioError(e));
    }
  }

  Future<Either<Failure, PrivacyRequest>> requestDeletion() async {
    try {
      final res = await _dio.post<Map<String, dynamic>>('/privacy/delete');
      return Right(PrivacyRequest.fromJson(res.data ?? const {}));
    } on DioException catch (e) {
      return Left(mapDioError(e));
    }
  }

  Future<Either<Failure, Unit>> cancelDeletion() async {
    try {
      await _dio.delete<void>('/privacy/delete');
      return const Right(unit);
    } on DioException catch (e) {
      return Left(mapDioError(e));
    }
  }
}
