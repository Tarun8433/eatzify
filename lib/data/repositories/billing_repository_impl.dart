import 'package:dartz/dartz.dart';
import 'package:health_pro/core/errors/failures.dart';
import 'package:health_pro/data/datasources/remote/billing_remote_data_source.dart';
import 'package:health_pro/domain/entities/billing.dart';
import 'package:health_pro/domain/repositories/billing_repository.dart';

class BillingRepositoryImpl implements BillingRepository {
  BillingRepositoryImpl(this._remote);

  final BillingRemoteDataSource _remote;

  @override
  Future<Either<Failure, Entitlements>> entitlements() => _remote.entitlements();

  @override
  Future<Either<Failure, List<TierPrice>>> prices() => _remote.prices();
}
