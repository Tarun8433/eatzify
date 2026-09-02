import 'package:dartz/dartz.dart';
import 'package:dio/dio.dart';
import 'package:health_pro/core/errors/failures.dart';
import 'package:health_pro/core/network/error_mapper.dart';
import 'package:health_pro/domain/entities/session.dart';

/// docs/09 §3 over dio.
///
/// `otp/request` and `otp/verify` are live in `api/src/auth`. OTP delivery is a dev stub today —
/// every number gets the fixed `OTP_DEV_CODE` — so this works end to end without an SMS provider.
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

  /// The endpoint this posts to does not exist in `api/src/auth` yet — see the contract on
  /// `AuthRepository.signInWithGoogle`. The request body is the minimum a verifier needs: the
  /// token, and the device the session belongs to.
  Future<Either<Failure, Session>> signInWithGoogle({
    required String idToken,
    required String deviceId,
  }) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        '/auth/google',
        data: {'id_token': idToken, 'device': deviceId},
      );
      return Right(_sessionFrom(res.data!));
    } on DioException catch (e) {
      return Left(mapDioError(e));
    }
  }

  /// `POST /auth/refresh` is guarded by `AuthGuard('jwt-refresh')`, which reads the REFRESH token
  /// from the Authorization header — not from the body. The auth interceptor has already put the
  /// (expired) ACCESS token there, so it has to be overridden here or every refresh 401s and the
  /// user is signed out the moment their access token ages out.
  ///
  /// The response is the boilerplate's `RefreshResponseDto` — `token` / `refreshToken`, not the
  /// `access` / `refresh` pair that `/auth/otp/verify` returns.
  Future<Either<Failure, Session>> refresh(Session current) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        '/auth/refresh',
        options: Options(headers: {'Authorization': 'Bearer ${current.refreshToken}'}),
      );
      final data = res.data!;
      return Right(
        current.copyWith(
          accessToken: data['token'] as String,
          refreshToken: data['refreshToken'] as String,
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
