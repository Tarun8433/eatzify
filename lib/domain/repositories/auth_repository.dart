import 'package:dartz/dartz.dart';
import 'package:health_pro/core/errors/failures.dart';
import 'package:health_pro/domain/entities/session.dart';

/// docs/09 §3. `Either` out of every use case, per docs/14's stack.
abstract class AuthRepository {
  /// `POST /auth/email/login` (D-250). An unknown email and a wrong password fail the same way, and
  /// an address never confirmed fails with `EMAIL_NOT_VERIFIED` after a fresh code is emailed.
  Future<Either<Failure, Session>> signIn({required String email, required String password});

  /// `POST /auth/email/register`. The account starts inactive; the emailed code opens it. The phone
  /// number is contact information only (Cashfree needs one per order), never a way in.
  Future<Either<Failure, Unit>> register({
    required String email,
    required String password,
    required String phoneE164,
  });

  /// `POST /auth/email/verify`. The emailed code, answered with a session.
  Future<Either<Failure, Session>> verifyEmail({required String email, required String code});

  /// `POST /auth/email/resend`. Answers the same whether or not the address has an account.
  Future<Either<Failure, Unit>> resendCode(String email);

  /// `POST /auth/forgot/password`. Emails a reset link; answers the same for unknown addresses.
  Future<Either<Failure, Unit>> forgotPassword(String email);

  /// `POST /auth/google`. Exchanges a Google ID token for a session.
  ///
  /// NOT in docs/09 §3. It is here because the sign-in screen offers
  /// the button, and the shape is the one every provider-token exchange has: the app never trusts
  /// the token, the server verifies it against Google's keys and decides who the user is.
  ///
  /// Returns the same [Session] as [signIn] on purpose — a Google user and an email user are the
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
