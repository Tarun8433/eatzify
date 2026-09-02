import 'package:dartz/dartz.dart';
import 'package:health_pro/core/errors/failures.dart';
import 'package:health_pro/domain/entities/plan.dart';

/// docs/09 §4.2.
abstract class PlanRepository {
  /// Generates today's plan. The targets it produces are read back through `GET /logs/day`.
  Future<Either<Failure, Unit>> generate();

  /// The current plan, or null when none has been generated.
  Future<Either<Failure, Plan?>> current();

  /// Foods this user may choose from, keyed by meal slot (D-82, D-85). Filtered server-side by
  /// their preference, allergies, budget and condition tags — the app never decides what is
  /// suitable for anybody, nor which meal a food belongs to.
  Future<Either<Failure, Map<String, List<FoodOption>>>> options();
}
