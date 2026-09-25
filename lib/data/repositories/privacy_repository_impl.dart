import 'package:dartz/dartz.dart';
import 'package:health_pro/core/errors/failures.dart';
import 'package:health_pro/data/datasources/remote/privacy_remote_data_source.dart';
import 'package:health_pro/domain/entities/privacy.dart';
import 'package:health_pro/domain/repositories/privacy_repository.dart';

class PrivacyRepositoryImpl implements PrivacyRepository {
  const PrivacyRepositoryImpl(this._remote);

  final PrivacyRemoteDataSource _remote;

  @override
  Future<Either<Failure, PrivacyState>> load() => _remote.load();

  @override
  Future<Either<Failure, List<ConsentItem>>> setConsent(String type, {required bool granted}) =>
      _remote.setConsent(type, granted: granted);

  @override
  Future<Either<Failure, PrivacyRequest>> requestExport() => _remote.requestExport();

  @override
  Future<Either<Failure, Map<String, dynamic>>> exportBundle(String requestId) =>
      _remote.exportBundle(requestId);

  @override
  Future<Either<Failure, PrivacyRequest>> requestDeletion() => _remote.requestDeletion();

  @override
  Future<Either<Failure, Unit>> cancelDeletion() => _remote.cancelDeletion();
}
