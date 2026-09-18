import 'package:dartz/dartz.dart';
import 'package:health_pro/core/errors/failures.dart';
import 'package:health_pro/domain/entities/billing.dart';

/// docs/09 §7. Entitlements, prices, and starting a purchase (D-194).
///
/// [checkout] takes no money and grants nothing — a verified webhook is the only thing that
/// activates a subscription (docs/11 §5). What comes back is a handle for the gateway.
abstract class BillingRepository {
  Future<Either<Failure, Entitlements>> entitlements();

  Future<Either<Failure, List<TierPrice>>> prices();

  /// [months] names a column of the price matrix; the SERVER reads the amount from it. Nothing
  /// here sends a price.
  ///
  /// [idempotencyKey] belongs to one attempt: a retry of that attempt returns the order it already
  /// opened rather than opening a second one.
  Future<Either<Failure, CheckoutSession>> checkout({
    required String tier,
    required int months,
    required String idempotencyKey,
    /// D-236: an offer code the server prices. The app never computes a discount (rule 2/3).
    String? couponCode,
  });

  /// docs/09 §7: the plan someone holds, its renewal date, and whether renewing needs the bank's
  /// approval.
  Future<Either<Failure, SubscriptionState>> subscription();

  /// docs/11 §6: the one free week. The SERVER decides whether this number may still have it.
  Future<Either<Failure, SubscriptionState>> startTrial(String tier);

  /// Stops the renewal and keeps the access already paid for (docs/09 §7). [reason] is optional —
  /// nobody owes an explanation for leaving.
  Future<Either<Failure, SubscriptionState>> cancelRenewal({String? reason});

  /// docs/11 §7's quote, before anything is charged.
  Future<Either<Failure, UpgradeQuote>> upgradeQuote({required String tier, required int months});

  /// Charges the difference the quote named. Like [checkout] it grants nothing by itself.
  Future<Either<Failure, CheckoutSession>> upgrade({
    required String tier,
    required int months,
    required String idempotencyKey,
  });

  /// Stub builds only, and the server refuses it anywhere else. Stands in for the gateway's
  /// webhook so the activation path is exercisable before Cashfree credentials exist.
  Future<Either<Failure, Unit>> completeStubPayment(String orderId);
}
