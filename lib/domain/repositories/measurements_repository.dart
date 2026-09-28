import 'package:dartz/dartz.dart';
import 'package:health_pro/core/errors/failures.dart';
import 'package:health_pro/domain/entities/measurement.dart';

/// docs/09 §4.
abstract class MeasurementsRepository {
  /// `is_suspect` true means the app shows a confirm dialog (docs/09 §4) — the value is already
  /// stored, so this is a "did you mean that?", not a rejection.
  Future<Either<Failure, ({Measurement measurement, bool isSuspect})>> record({
    required String kind,
    required double value,
    required String unit,

    /// Defaults to manual, which is what every hand-entry screen means (D-97). A sync passes its
    /// platform, and the SERVER decides whether that is allowed to overwrite what is there.
    MeasurementSource source,

    /// When the reading was taken, if not now. The SERVER still decides which diary day that
    /// instant belongs to (CLAUDE.md rule 8) — this only says when it happened.
    DateTime? at,
  });

  /// `POST /measurements/bulk` (D-216) — a health-platform sync, in one request.
  ///
  /// Right means the request was answered, not that every reading stuck: the server still refuses
  /// to let a device overwrite a hand-typed figure (D-97), and reports that per reading. A sync has
  /// nothing to show anybody about either, so this does not pass the detail on.
  Future<Either<Failure, Unit>> recordMany(List<NewMeasurement> readings);

  Future<Either<Failure, MeasurementHistory>> history(String kind);
}
