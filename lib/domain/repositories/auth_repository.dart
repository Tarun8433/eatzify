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

  /// `POST /auth/google`. Exchanges a Google ID token for a session.
  ///
  /// NOT in docs/09 §3, which knows only phone + OTP. It is here because the sign-in screen offers
  /// the button, and the shape is the one every provider-token exchange has: the app never trusts
  /// the token, the server verifies it against Google's keys and decides who the user is.
  ///
  /// Returns the same [Session] as [verifyOtp] on purpose — a Google user and a phone user are the
  /// same user to every screen after this one.
  Future<Either<Failure, Session>> signInWithGoogle({
    required String idToken,
    required String deviceId,
  });

  /// `POST /auth/refresh`. Rotates; docs/09 says reuse revokes the whole token family.
  Future<Either<Failure, Session>> refresh(Session current);

  /// `POST /auth/logout`. Best-effort server-side revocation; local state is cleared regardless.
  Future<Either<Failure, Unit>> logout(Session current);
}
