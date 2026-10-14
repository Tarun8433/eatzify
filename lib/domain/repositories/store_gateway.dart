import 'package:health_pro/domain/repositories/payment_gateway.dart';

/// Payments plan, Phases 4–5: the platform store (Google Play on Android, StoreKit 2 on iOS).
///
/// Same rule as [PaymentGateway]: what the store says is never proof. Every purchase token goes to
/// the server's verify route, which re-reads it from Google or Apple, and the app then asks the server
/// what the account may use.
abstract class StoreGateway {
  /// Opens the store's purchase sheet. [basePlanId] is Play's; the App Store has none. [accountToken]
  /// is the server's opaque id for this account, so the purchase cannot be claimed by another one.
  ///
  /// D-265: [offerId] buys that Play offer on the base plan instead of the base price — and fails
  /// as `productUnavailable` rather than quietly selling the full price when Play has no such
  /// offer. [offerCode] is the personal offer it redeems, handed to the server's verify.
  Future<PaymentResult> buy({
    required String productId,
    required String? basePlanId,
    required String accountToken,
    String? offerId,
    String? offerCode,
  });

  /// D-265: what Play's own sheet will charge for that offer, formatted by Play ("₹199"), or null
  /// when the store cannot say — the caller then shows no figure rather than a guessed one.
  Future<String?> offerPrice({
    required String productId,
    required String basePlanId,
    required String offerId,
  });

  /// Re-sends any purchase the store holds but the server never confirmed — a verify that failed
  /// on a bad network, or a pending payment that cleared while the app was closed. Once per run.
  Future<void> resumePending();
}

/// D-266: how one store purchase ended, as the app saw it. [pending] is a purchase the store holds
/// for later (a UPI payment still clearing); [refused] is one the server would not verify.
enum StoreAttemptOutcome { cancelled, failed, pending, purchased, refused }

/// D-266: one finished [StoreGateway.buy], reported to the server so support can see failed attempts
/// that otherwise never reach it. No amount, no payment details — the plan asked for, how it ended
/// and the store's own code.
class StoreAttempt {
  const StoreAttempt({
    required this.provider,
    required this.productId,
    required this.outcome,
    this.basePlanId,
    this.offerId,
    this.reason,
    this.storeCode,
  });

  /// `play` or `app_store`, as the server names them.
  final String provider;
  final String productId;
  final String? basePlanId;
  final String? offerId;
  final StoreAttemptOutcome outcome;

  /// A [PaymentFailureReason] name, or `serverRefused`.
  final String? reason;
  final String? storeCode;
}
