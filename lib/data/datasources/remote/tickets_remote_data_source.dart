import 'package:dartz/dartz.dart';
import 'package:dio/dio.dart';
import 'package:health_pro/core/errors/failures.dart';
import 'package:health_pro/core/network/error_mapper.dart';
import 'package:health_pro/domain/entities/support_ticket.dart';

/// `/tickets` (docs/09 §9's user-facing half).
class TicketsRemoteDataSource {
  const TicketsRemoteDataSource(this._dio);

  final Dio _dio;

  Future<Either<Failure, List<SupportTicket>>> list() async {
    try {
      final res = await _dio.get<List<dynamic>>('/tickets');
      return Right([
        for (final row in res.data ?? const []) SupportTicket.fromJson(row as Map<String, dynamic>),
      ]);
    } on DioException catch (e) {
      return Left(mapDioError(e));
    }
  }

  Future<Either<Failure, SupportTicket>> open({
    required String subject,
    required String body,
    String? requestId,
  }) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        '/tickets',
        data: {
          'subject': subject,
          'body': body,
          if (requestId != null && requestId.isNotEmpty) 'request_id': requestId,
        },
      );
      return Right(SupportTicket.fromJson(res.data ?? const {}));
    } on DioException catch (e) {
      return Left(mapDioError(e));
    }
  }

  Future<Either<Failure, SupportThread>> thread(String id) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>('/tickets/$id');
      final data = res.data ?? const <String, dynamic>{};
      return Right((
        ticket: SupportTicket.fromJson(data),
        messages: [
          for (final row in data['messages'] as List? ?? const [])
            SupportMessage.fromJson(row as Map<String, dynamic>),
        ],
      ));
    } on DioException catch (e) {
      return Left(mapDioError(e));
    }
  }

  Future<Either<Failure, Unit>> reply(String id, String body) async {
    try {
      await _dio.post<void>('/tickets/$id/reply', data: {'body': body});
      return const Right(unit);
    } on DioException catch (e) {
      return Left(mapDioError(e));
    }
  }
}
