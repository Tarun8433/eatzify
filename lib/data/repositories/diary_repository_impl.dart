import 'package:dartz/dartz.dart';
import 'package:health_pro/core/errors/failures.dart';
import 'package:health_pro/data/datasources/remote/diary_remote_data_source.dart';
import 'package:health_pro/domain/entities/food.dart';
import 'package:health_pro/domain/repositories/diary_repository.dart';

class DiaryRepositoryImpl implements DiaryRepository {
  const DiaryRepositoryImpl(this._remote);

  final DiaryRemoteDataSource _remote;

  @override
  Future<Either<Failure, List<Food>>> searchFoods(
    String query, {
    int limit = 20,
    int offset = 0,
    String? suitableFor,
  }) => _remote.searchFoods(query, limit: limit, offset: offset, suitableFor: suitableFor);

  @override
  Future<Either<Failure, LogEntry>> logFood({
    required String slot,
    required String foodId,
    String? measure,
    double? measureCount,
    double? quantityG,
  }) => _remote.logFood(
    slot: slot,
    foodId: foodId,
    measure: measure,
    measureCount: measureCount,
    quantityG: quantityG,
  );

  @override
  Future<Either<Failure, DiaryDay>> day({String? date}) => _remote.day(date: date);

  @override
  Future<Either<Failure, Unit>> remove(String id) => _remote.remove(id);
}
