import 'package:dartz/dartz.dart';
import 'package:dio/dio.dart';
import 'package:health_pro/core/errors/failures.dart';
import 'package:health_pro/core/network/error_mapper.dart';
import 'package:health_pro/domain/entities/session.dart';

/// docs/09 §3 over dio.
///
/// The API does not exist yet — `api/src/auth` is the boilerplate's email flow, not phone OTP
/// (docs/20 §2 pruned social sign-in for exactly that reason). Every call here is real and will
/// work unchanged once E1 lands the endpoints; today they surface an honest ApiFailure.
class AuthRemoteDataSource {
  const AuthRemoteDataSource(this._dio);

  final Dio _dio;

  Future<Either<Failure, Unit>> requestOtp(String phoneE164) async {
    try {
      await _dio.post<void>('/auth/otp/request', data: {'phone_e164': phoneE164});
      return const Right(unit);
    } on DioException catch (e) {
      return Left(mapDioError(e));
    }
  }

  Future<Either<Failure, Session>> verifyOtp({
    required String phoneE164,
    required String otp,
    required String deviceId,
  }) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        '/auth/otp/verify',
        data: {'phone_e164': phoneE164, 'otp': otp, 'device': deviceId},
      );
      return Right(_sessionFrom(res.data!));
    } on DioException catch (e) {
      return Left(mapDioError(e));
    }
  }

  Future<Either<Failure, Session>> refresh(Session current) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        '/auth/refresh',
        data: {'refresh': current.refreshToken},
      );
      final data = res.data!;
      return Right(
        current.copyWith(
          accessToken: data['access'] as String,
          refreshToken: data['refresh'] as String,
        ),
      );
    } on DioException catch (e) {
      return Left(mapDioError(e));
    }
  }

  Future<Either<Failure, Unit>> logout(Session current) async {
    try {
      await _dio.post<void>('/auth/logout', data: {'refresh': current.refreshToken});
      return const Right(unit);
    } on DioException catch (e) {
      return Left(mapDioError(e));
    }
  }

  Session _sessionFrom(Map<String, dynamic> json) {
    final user = json['user'] as Map<String, dynamic>? ?? const {};
    return Session(
      accessToken: json['access'] as String,
      refreshToken: json['refresh'] as String,
      userId: user['id']?.toString() ?? '',
      roles: (user['roles'] as List?)?.map((r) => r.toString()).toList() ?? const [],
      onboardingRequired: json['onboarding_required'] as bool? ?? true,
    );
  }
}
