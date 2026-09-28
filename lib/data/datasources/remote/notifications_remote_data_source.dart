import 'package:dartz/dartz.dart';
import 'package:dio/dio.dart';
import 'package:health_pro/core/errors/failures.dart';
import 'package:health_pro/core/network/error_mapper.dart';
import 'package:health_pro/domain/entities/app_notification.dart';

/// `GET /notifications` and the two read markers.
class NotificationsRemoteDataSource {
  const NotificationsRemoteDataSource(this._dio);

  final Dio _dio;

  Future<Either<Failure, NotificationFeed>> list({DateTime? before}) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        '/notifications',
        queryParameters: {
          // A cursor, not a page number (api-conventions), and not health data.
          if (before != null) 'before': before.toUtc().toIso8601String(),
        },
      );
      final data = res.data ?? const {};
      return Right((
        items: (data['items'] as List? ?? const [])
            .map((e) => AppNotification.fromJson(e as Map<String, dynamic>))
            .toList(),
        unreadCount: (data['unread_count'] as num?)?.toInt() ?? 0,
      ));
    } on DioException catch (e) {
      return Left(mapDioError(e));
    }
  }

  Future<Either<Failure, Unit>> markRead(String id) => _post('/notifications/$id/read');

  Future<Either<Failure, Unit>> markAllRead() => _post('/notifications/read-all');

  Future<Either<Failure, Unit>> _post(String path) async {
    try {
      await _dio.post<void>(path);
      return const Right(unit);
    } on DioException catch (e) {
      return Left(mapDioError(e));
    }
  }
}
