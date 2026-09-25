import 'package:dartz/dartz.dart';
import 'package:dio/dio.dart';
import 'package:health_pro/core/errors/failures.dart';
import 'package:health_pro/core/network/error_mapper.dart';
import 'package:health_pro/domain/entities/measurement.dart';

/// docs/09 §4 over dio.
class MeasurementsRemoteDataSource {
  const MeasurementsRemoteDataSource(this._dio);

  final Dio _dio;

  /// `POST /measurements`. The server decides the diary day and whether the value is suspect.
  Future<Either<Failure, ({Measurement measurement, bool isSuspect})>> record({
    required String kind,
    required double value,
    required String unit,
    MeasurementSource source = MeasurementSource.manual,
    DateTime? at,
  }) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        '/measurements',
        data: {
          'kind': kind,
          'value': value,
          'unit': unit,
          'source': source.wire,
          // UTC on the wire (docs/08): the server reads the instant and derives the diary day from
          // it. Omitted entirely when the reading is now, which is what the server assumes anyway.
          if (at != null) 'recorded_at': at.toUtc().toIso8601String(),
        },
      );
      final data = res.data!;
      return Right((
        measurement: Measurement.fromJson(data['measurement'] as Map<String, dynamic>),
        isSuspect: data['is_suspect'] as bool? ?? false,
      ));
    } on DioException catch (e) {
      return Left(mapDioError(e));
    }
  }

  /// `POST /measurements/bulk` (D-216).
  Future<Either<Failure, Unit>> recordMany(List<NewMeasurement> readings) async {
    try {
      await _dio.post<Map<String, dynamic>>(
        '/measurements/bulk',
        data: {
          'readings': [
            for (final r in readings)
              {
                'kind': r.kind,
                'value': r.value,
                'unit': r.unit,
                'source': r.source.wire,
                'recorded_at': r.at.toUtc().toIso8601String(),
                if (r.replaceManual) 'replace_manual': true,
              },
          ],
        },
      );
      return const Right(unit);
    } on DioException catch (e) {
      return Left(mapDioError(e));
    }
  }

  Future<Either<Failure, MeasurementHistory>> history(String kind) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>('/measurements/$kind');
      return Right(MeasurementHistory.fromJson(res.data ?? const {}));
    } on DioException catch (e) {
      return Left(mapDioError(e));
    }
  }
}
