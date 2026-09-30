import 'package:health_pro/domain/repositories/payment_gateway.dart';

/// Payments plan, Phases 4–5: the platform store (Google Play on Android, StoreKit 2 on iOS).
///
/// Same rule as [PaymentGateway]: what the store says is never proof. Every purchase token goes to
/// the server's verify route, which re-reads it from Google or Apple, and the app then asks the server
/// what the account may use.
abstract class StoreGateway {
  /// Opens the store's purchase sheet. [basePlanId] is Play's; the App Store has none. [accountToken]
  /// is the server's opaque id for this account, so the purchase cannot be claimed by another one.
  Future<PaymentResult> buy({
    required String productId,
    required String? basePlanId,
    required String accountToken,
  });

  /// Re-sends any purchase the store holds but the server never confirmed — a verify that failed
  /// on a bad network, or a pending payment that cleared while the app was closed. Once per run.
  Future<void> resumePending();
}
