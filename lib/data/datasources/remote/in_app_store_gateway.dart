import 'dart:async';

import 'package:health_pro/domain/repositories/payment_gateway.dart';
import 'package:health_pro/domain/repositories/store_gateway.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/billing_client_wrappers.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';

/// Sends a purchase token to the server. Returns the server's `user_message` when it refused, or
/// null when the purchase is now on the account.
typedef VerifyPurchase = Future<String?> Function(String purchaseToken);

/// Google Play Billing and StoreKit 2, wrapped so the rest of the app never imports the plugin.
/// [verify] is the platform's own server route (`play/verify` or `appstore/verify`).
///
/// The store reports every purchase on one process-wide stream, including ones that finish after the
/// sheet closed (a pending UPI payment). So this listens from construction, verifies whatever
/// arrives, and routes the answer to the [buy] that is waiting, if any. A purchase nobody waits on
/// is still verified — the money moved, the account must get it.
class InAppStoreGateway implements StoreGateway {
  InAppStoreGateway({required this.verify, InAppPurchase? iap})
    : _iap = iap ?? InAppPurchase.instance {
    // ponytail: never cancelled — a permanent singleton that lives as long as the process.
    // ignore: cancel_subscriptions
    _iap.purchaseStream.listen(_onPurchases, onError: (_) => _finish(_failed(null)));
  }

  final VerifyPurchase verify;
  final InAppPurchase _iap;

  String? _pendingProduct;
  Completer<PaymentResult>? _waiting;
  bool _resumed = false;

  @override
  Future<PaymentResult> buy({
    required String productId,
    required String? basePlanId,
    required String accountToken,
  }) async {
    // A second tap while the sheet is up would leave the first caller waiting forever.
    if (_waiting != null && !_waiting!.isCompleted) return const PaymentResult.cancelled();
    if (!await _iap.isAvailable()) return _failed(null);

    final found = await _iap.queryProductDetails({productId});
    final param = _param(found.productDetails, basePlanId, accountToken);
    if (param == null) return _failed(found.error?.message);

    final waiting = Completer<PaymentResult>();
    _pendingProduct = productId;
    _waiting = waiting;

    try {
      final launched = await _iap.buyNonConsumable(purchaseParam: param);
      if (!launched) _finish(_failed(null));
    } on Exception catch (e) {
      _finish(_failed(e.toString()));
    }
    return waiting.future;
  }

  @override
  Future<void> resumePending() async {
    if (_resumed) return;
    _resumed = true;
    if (!await _iap.isAvailable()) return;
    // Owned purchases come back on the stream as `restored`; [_onPurchases] verifies the ones
    // still unacknowledged.
    await _iap.restorePurchases();
  }

  Future<void> _onPurchases(List<PurchaseDetails> purchases) async {
    for (final p in purchases) {
      final waitedOn = p.productID == _pendingProduct;
      switch (p.status) {
        case PurchaseStatus.pending:
          // Money has not moved. Nothing to verify yet; Play re-reports it when it clears.
          if (waitedOn) _finish(const PaymentResult.submitted());
        case PurchaseStatus.canceled:
          if (waitedOn) _finish(const PaymentResult.cancelled());
        case PurchaseStatus.error:
          if (waitedOn) _finish(_failed(p.error?.message));
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          // A restored purchase already acknowledged is one the server already has.
          if (p.status == PurchaseStatus.restored && !p.pendingCompletePurchase) continue;
          final refused = await verify(p.verificationData.serverVerificationData);
          // The server acknowledges on verify; this is the backup, and Play ignores a second one.
          if (refused == null && p.pendingCompletePurchase) {
            await _iap.completePurchase(p).catchError((_) {});
          }
          if (waitedOn) {
            _finish(
              refused == null
                  ? const PaymentResult.submitted()
                  : PaymentResult(PaymentOutcome.failed, message: refused),
            );
          }
      }
    }
  }

  void _finish(PaymentResult result) {
    final waiting = _waiting;
    _pendingProduct = null;
    _waiting = null;
    if (waiting != null && !waiting.isCompleted) waiting.complete(result);
  }

  static PaymentResult _failed(String? message) =>
      PaymentResult(PaymentOutcome.failed, message: message);

  /// Play: the base plan's own offer (no offer id) before any promotional offer on it.
  /// App Store (no [basePlanId]): the product itself; the account token must be a UUID.
  static PurchaseParam? _param(
    List<ProductDetails> found,
    String? basePlanId,
    String accountToken,
  ) {
    if (basePlanId == null) {
      final product = found.firstOrNull;
      return product == null
          ? null
          : PurchaseParam(productDetails: product, applicationUserName: accountToken);
    }
    final plans = found.whereType<GooglePlayProductDetails>().where(
      (d) => _basePlanOf(d) == basePlanId,
    );
    final offer = plans.where((d) => _offerOf(d) == null).firstOrNull ?? plans.firstOrNull;
    return offer == null
        ? null
        : GooglePlayPurchaseParam(productDetails: offer, applicationUserName: accountToken);
  }

  static String? _basePlanOf(GooglePlayProductDetails d) => _offer(d)?.basePlanId;

  static String? _offerOf(GooglePlayProductDetails d) => _offer(d)?.offerId;

  static SubscriptionOfferDetailsWrapper? _offer(GooglePlayProductDetails d) {
    final index = d.subscriptionIndex;
    final offers = d.productDetails.subscriptionOfferDetails;
    return index == null || offers == null || index >= offers.length ? null : offers[index];
  }
}
