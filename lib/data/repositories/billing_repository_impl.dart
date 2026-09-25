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

  @override
  Future<Either<Failure, CheckoutSession>> checkout({
    required String tier,
    required int months,
    required String idempotencyKey,
    String? couponCode,
  }) => _remote.checkout(
    tier: tier,
    months: months,
    idempotencyKey: idempotencyKey,
    couponCode: couponCode,
  );

  @override
  Future<Either<Failure, SubscriptionState>> subscription() => _remote.subscription();

  @override
  Future<Either<Failure, SubscriptionState>> startTrial(String tier) => _remote.startTrial(tier);

  @override
  Future<Either<Failure, SubscriptionState>> cancelRenewal({String? reason}) =>
      _remote.cancelRenewal(reason: reason);

  @override
  Future<Either<Failure, UpgradeQuote>> upgradeQuote({required String tier, required int months}) =>
      _remote.upgradeQuote(tier: tier, months: months);

  @override
  Future<Either<Failure, CheckoutSession>> upgrade({
    required String tier,
    required int months,
    required String idempotencyKey,
  }) => _remote.upgrade(tier: tier, months: months, idempotencyKey: idempotencyKey);

  @override
  Future<Either<Failure, Unit>> completeStubPayment(String orderId) =>
      _remote.completeStubPayment(orderId);
}
