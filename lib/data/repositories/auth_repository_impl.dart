import 'package:dartz/dartz.dart';
import 'package:health_pro/core/errors/failures.dart';
import 'package:health_pro/data/datasources/remote/auth_remote_data_source.dart';
import 'package:health_pro/domain/entities/session.dart';
import 'package:health_pro/domain/repositories/auth_repository.dart';

class AuthRepositoryImpl implements AuthRepository {
  const AuthRepositoryImpl(this._remote);

  final AuthRemoteDataSource _remote;

  @override
  Future<Either<Failure, Unit>> requestOtp(String phoneE164) => _remote.requestOtp(phoneE164);

  @override
  Future<Either<Failure, Session>> verifyOtp({
    required String phoneE164,
    required String otp,
    required String deviceId,
  }) => _remote.verifyOtp(phoneE164: phoneE164, otp: otp, deviceId: deviceId);

  @override
  Future<Either<Failure, Session>> refresh(Session current) => _remote.refresh(current);

  @override
  Future<Either<Failure, Unit>> logout(Session current) => _remote.logout(current);
}
