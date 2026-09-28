import 'package:dartz/dartz.dart';
import 'package:health_pro/core/errors/failures.dart';
import 'package:health_pro/domain/entities/food.dart';
import 'package:health_pro/domain/entities/food_scan.dart';

/// Meal-photo scanning (D-238, D-240): the photo goes up once, comes back as an estimate of the
/// plate, and becomes a diary entry only when the user says yes.
abstract class ScanRepository {
  Future<Either<Failure, ScanStatus>> status();

  /// [adWatched] is true once a rewarded ad paid out, for a tier that requires one.
  Future<Either<Failure, ScanEstimate>> scan(
    String filePath,
    String fileName, {
    required bool adWatched,
  });

  /// "Yes": logs the items at [keep] (indexes into the estimate) to [slot] as one entry with the
  /// photo. The server sums them — the app sends which items, never numbers.
  Future<Either<Failure, LogEntry>> confirm(
    int scanId, {
    required String slot,
    required List<int> keep,
  });

  /// "No": the server deletes the photo now rather than at the nightly sweep.
  Future<Either<Failure, Unit>> discard(int scanId);
}
