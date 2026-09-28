import 'package:dartz/dartz.dart';
import 'package:dio/dio.dart';
import 'package:health_pro/core/errors/failures.dart';
import 'package:health_pro/core/network/error_mapper.dart';
import 'package:health_pro/domain/entities/chat.dart';

/// docs/09 §6's chat routes over dio. The socket is a faster path to the same rows; this one is
/// what the screen is actually built on, so a phone with no socket still has a conversation.
class ChatRemoteDataSource {
  const ChatRemoteDataSource(this._dio);

  final Dio _dio;

  Future<Either<Failure, List<ChatThread>>> threads() async {
    try {
      final res = await _dio.get<List<dynamic>>('/coach/threads');
      final rows = res.data ?? const [];
      return Right(rows.map((r) => ChatThread.fromJson(r as Map<String, dynamic>)).toList());
    } on DioException catch (e) {
      return Left(mapDioError(e));
    }
  }

  Future<Either<Failure, List<ChatMessage>>> messages(int otherUserId, {DateTime? before}) async {
    try {
      final res = await _dio.get<List<dynamic>>(
        '/coach/messages/$otherUserId',
        queryParameters: {if (before != null) 'before': before.toUtc().toIso8601String()},
      );
      final rows = res.data ?? const [];
      return Right(rows.map((r) => ChatMessage.fromJson(r as Map<String, dynamic>)).toList());
    } on DioException catch (e) {
      return Left(mapDioError(e));
    }
  }

  Future<Either<Failure, ChatMessage>> send(int otherUserId, String body) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        '/coach/messages',
        // docs/09 §6 names the field from the coach's side; the server takes either and means the
        // same thing, so the app sends the one that reads honestly from both ends.
        data: {'other_user_id': otherUserId, 'body': body},
      );
      return Right(ChatMessage.fromJson(res.data ?? const {}));
    } on DioException catch (e) {
      return Left(mapDioError(e));
    }
  }

  Future<Either<Failure, Unit>> markRead(int otherUserId) async {
    try {
      await _dio.post<void>('/coach/messages/$otherUserId/read');
      return const Right(unit);
    } on DioException catch (e) {
      return Left(mapDioError(e));
    }
  }
}
