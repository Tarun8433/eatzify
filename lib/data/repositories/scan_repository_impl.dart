import 'package:dartz/dartz.dart';
import 'package:health_pro/core/errors/failures.dart';
import 'package:health_pro/data/datasources/remote/scan_remote_data_source.dart';
import 'package:health_pro/domain/entities/food.dart';
import 'package:health_pro/domain/entities/food_scan.dart';
import 'package:health_pro/domain/repositories/scan_repository.dart';

class ScanRepositoryImpl implements ScanRepository {
  const ScanRepositoryImpl(this._remote);

  final ScanRemoteDataSource _remote;

  @override
  Future<Either<Failure, ScanStatus>> status() => _remote.status();

  @override
  Future<Either<Failure, ScanEstimate>> scan(
    String filePath,
    String fileName, {
    required bool adWatched,
  }) => _remote.scan(filePath, fileName, adWatched: adWatched);

  @override
  Future<Either<Failure, LogEntry>> confirm(
    int scanId, {
    required String slot,
    required List<int> keep,
  }) => _remote.confirm(scanId, slot: slot, keep: keep);

  @override
  Future<Either<Failure, Unit>> discard(int scanId) => _remote.discard(scanId);
}
