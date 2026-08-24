import 'package:dartz/dartz.dart';
import 'package:health_pro/core/errors/failures.dart';
import 'package:health_pro/domain/entities/session.dart';

/// docs/09 §3. `Either` out of every use case, per docs/14's stack.
abstract class AuthRepository {
  /// `POST /auth/otp/request`. Returns unit on success — docs/09: never reveal whether a number
  /// exists, so a valid and an unknown number look identical from here.
  Future<Either<Failure, Unit>> requestOtp(String phoneE164);

  /// `POST /auth/otp/verify`.
  Future<Either<Failure, Session>> verifyOtp({
    required String phoneE164,
    required String otp,
    required String deviceId,
  });

  /// `POST /auth/refresh`. Rotates; docs/09 says reuse revokes the whole token family.
  Future<Either<Failure, Session>> refresh(Session current);

  /// `POST /auth/logout`. Best-effort server-side revocation; local state is cleared regardless.
  Future<Either<Failure, Unit>> logout(Session current);
}
