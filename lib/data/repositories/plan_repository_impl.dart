import 'package:dartz/dartz.dart';
import 'package:health_pro/core/errors/failures.dart';
import 'package:health_pro/data/datasources/remote/plan_remote_data_source.dart';
import 'package:health_pro/domain/entities/plan.dart';
import 'package:health_pro/domain/repositories/plan_repository.dart';

class PlanRepositoryImpl implements PlanRepository {
  const PlanRepositoryImpl(this._remote);

  final PlanRemoteDataSource _remote;

  @override
  Future<Either<Failure, Unit>> generate() => _remote.generate();

  @override
  Future<Either<Failure, Plan?>> current() => _remote.current();

  @override
  Future<Either<Failure, Map<String, List<FoodOption>>>> options() => _remote.options();
}
