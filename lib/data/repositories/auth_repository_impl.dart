import 'package:dartz/dartz.dart';
import 'package:health_pro/core/errors/failures.dart';
import 'package:health_pro/data/datasources/remote/auth_remote_data_source.dart';
import 'package:health_pro/domain/entities/session.dart';
import 'package:health_pro/domain/repositories/auth_repository.dart';

class AuthRepositoryImpl implements AuthRepository {
  const AuthRepositoryImpl(this._remote);

  final AuthRemoteDataSource _remote;

  @override
  Future<Either<Failure, Session>> signIn({required String email, required String password}) =>
      _remote.signIn(email: email, password: password);

  @override
  Future<Either<Failure, Unit>> register({
    required String email,
    required String password,
    required String phoneE164,
  }) => _remote.register(email: email, password: password, phoneE164: phoneE164);

  @override
  Future<Either<Failure, Session>> verifyEmail({required String email, required String code}) =>
      _remote.verifyEmail(email: email, code: code);

  @override
  Future<Either<Failure, Unit>> resendCode(String email) => _remote.resendCode(email);

  @override
  Future<Either<Failure, Unit>> forgotPassword(String email) => _remote.forgotPassword(email);

  @override
  Future<Either<Failure, Session>> signInWithGoogle({
    required String idToken,
    required String deviceId,
  }) => _remote.signInWithGoogle(idToken: idToken, deviceId: deviceId);

  @override
  Future<Either<Failure, Session>> refresh(Session current) => _remote.refresh(current);

  @override
  Future<Either<Failure, Unit>> logout(Session current) => _remote.logout(current);
}
