import 'package:dartz/dartz.dart';
import 'package:health_pro/core/errors/failures.dart';
import 'package:health_pro/domain/entities/food.dart';

/// docs/09 §5.
abstract class DiaryRepository {
  /// `GET /foods`. An empty [query] is the browse case — the whole verified table, alphabetical.
  ///
  /// Paged, because it is ~280 rows with a photograph each and the tab opens on all of them
  /// (D-121). [offset] is where the next page starts; the server's order is total, so a boundary
  /// lands in the same place every time.
  /// [suitableFor] is a `FoodPreference.wire` (docs/03 §2) — the category control on the food
  /// tab. Filtering is the SERVER's job: the list is paged, so a client-side filter would only
  /// ever filter the pages already fetched.
  Future<Either<Failure, List<Food>>> searchFoods(
    String query, {
    int limit,
    int offset,
    String? suitableFor,
  });

  Future<Either<Failure, LogEntry>> logFood({
    required String slot,
    required String foodId,
    String? measure,
    double? measureCount,
    double? quantityG,
  });

  /// Today's diary. `targets` is null when no plan exists — not zero.
  /// [date] is an ISO `yyyy-MM-dd` diary date; null is today. The SERVER decides where a day
  /// begins and ends (CLAUDE.md rule 8) — this only asks for one it has already decided.
  Future<Either<Failure, DiaryDay>> day({String? date});

  /// docs/08: refused with LOG_LOCKED once the 48 h window has passed.
  Future<Either<Failure, Unit>> remove(String id);
}
