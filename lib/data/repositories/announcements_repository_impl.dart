import 'package:dartz/dartz.dart';
import 'package:dio/dio.dart';
import 'package:health_pro/core/errors/failures.dart';
import 'package:health_pro/core/network/error_mapper.dart';
import 'package:health_pro/domain/entities/announcement.dart';
import 'package:health_pro/domain/repositories/announcements_repository.dart';

/// One GET, so no separate data source: the mapping is the whole of it.
class AnnouncementsRepositoryImpl implements AnnouncementsRepository {
  const AnnouncementsRepositoryImpl(this._dio);

  final Dio _dio;

  @override
  Future<Either<Failure, List<Announcement>>> active() async {
    try {
      final res = await _dio.get<List<dynamic>>('/announcements');
      return Right([
        for (final row in res.data ?? const <dynamic>[])
          if (row is Map<String, dynamic>) Announcement.fromJson(row),
      ]);
    } on DioException catch (e) {
      return Left(mapDioError(e));
    }
  }
}
