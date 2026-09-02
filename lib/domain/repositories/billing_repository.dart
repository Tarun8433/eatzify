import 'package:dartz/dartz.dart';
import 'package:health_pro/core/errors/failures.dart';
import 'package:health_pro/domain/entities/billing.dart';

/// docs/09 §7, the two endpoints that exist today: entitlements and prices. Checkout, verify and
/// the rest of the purchase path are not built server-side yet (D-134), so nothing here pretends
/// to buy anything.
abstract class BillingRepository {
  Future<Either<Failure, Entitlements>> entitlements();

  Future<Either<Failure, List<TierPrice>>> prices();
}
