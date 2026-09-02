import 'package:dartz/dartz.dart';
import 'package:health_pro/core/errors/failures.dart';
import 'package:health_pro/data/datasources/remote/measurements_remote_data_source.dart';
import 'package:health_pro/domain/entities/measurement.dart';
import 'package:health_pro/domain/repositories/measurements_repository.dart';

class MeasurementsRepositoryImpl implements MeasurementsRepository {
  const MeasurementsRepositoryImpl(this._remote);

  final MeasurementsRemoteDataSource _remote;

  @override
  Future<Either<Failure, ({Measurement measurement, bool isSuspect})>> record({
    required String kind,
    required double value,
    required String unit,
    MeasurementSource source = MeasurementSource.manual,
    DateTime? at,
  }) => _remote.record(kind: kind, value: value, unit: unit, source: source, at: at);

  @override
  Future<Either<Failure, MeasurementHistory>> history(String kind) => _remote.history(kind);
}
