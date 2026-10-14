import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:health_pro/domain/repositories/payment_gateway.dart';
import 'package:health_pro/domain/repositories/store_gateway.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/billing_client_wrappers.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';

/// Sends a purchase token to the server. Returns the server's `user_message` when it refused, or
/// null when the purchase is now on the account. [offerCode] is the personal offer (D-265) the
/// purchase redeemed, when it was bought from one.
typedef VerifyPurchase = Future<String?> Function(String purchaseToken, {String? offerCode});

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
  String? _pendingOfferCode;
  Completer<PaymentResult>? _waiting;
  bool _resumed = false;

  @override
  Future<PaymentResult> buy({
    required String productId,
    required String? basePlanId,
    required String accountToken,
    String? offerId,
    String? offerCode,
  }) async {
    // A second tap while the sheet is up would leave the first caller waiting forever.
    if (_waiting != null && !_waiting!.isCompleted) return const PaymentResult.cancelled();
    if (!await _iap.isAvailable()) {
      // Reaches logcat in release too. Store names only — nothing about the person.
      debugPrint('store: billing unavailable (not installed from the store, or no store account)');
      return _failed(null, PaymentFailureReason.storeUnavailable);
    }

    final found = await _iap.queryProductDetails({productId});
    final param = _param(found.productDetails, basePlanId, accountToken, offerId: offerId);
    if (param == null) {
      debugPrint(
        'store: no offer for $productId/${basePlanId ?? '-'}/${offerId ?? '-'} '
        '(not found: ${found.notFoundIDs}, error: ${found.error?.message})',
      );
      return _failed(found.error?.message, PaymentFailureReason.productUnavailable);
    }

    final waiting = Completer<PaymentResult>();
    _pendingProduct = productId;
    _pendingOfferCode = offerCode;
    _waiting = waiting;

    try {
      final launched = await _iap.buyNonConsumable(purchaseParam: param);
      if (!launched) {
        debugPrint('store: purchase sheet did not launch for $productId');
        _finish(_failed(null));
      }
    } on Exception catch (e) {
      debugPrint('store: purchase sheet failed to open for $productId: $e');
      _finish(_failed(null, PaymentFailureReason.storeFailed));
    }
    return waiting.future;
  }

  @override
  Future<String?> offerPrice({
    required String productId,
    required String basePlanId,
    required String offerId,
  }) async {
    try {
      if (!await _iap.isAvailable()) return null;
      final found = await _iap.queryProductDetails({productId});
      // Play's figure for the offer's first pricing phase — what its sheet opens on.
      return _param(found.productDetails, basePlanId, '', offerId: offerId)?.productDetails.price;
    } on Exception catch (e) {
      debugPrint('store: offer price unavailable for $productId/$basePlanId/$offerId: $e');
      return null;
    }
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
      // Play reports a closed sheet, or an error before any purchase exists, as one event with NO
      // product id. Only one purchase is ever in flight, so a nameless event is that one's answer —
      // matching on the id alone left it waiting forever, and the paywall stuck on "Please wait…".
      final waitedOn = _waiting != null && (p.productID == _pendingProduct || p.productID.isEmpty);
      switch (p.status) {
        case PurchaseStatus.pending:
          // Money has not moved. Nothing to verify yet; Play re-reports it when it clears.
          if (waitedOn) _finish(const PaymentResult.submitted());
        case PurchaseStatus.canceled:
          if (waitedOn) _finish(const PaymentResult.cancelled());
        case PurchaseStatus.error:
          if (waitedOn) _finish(_storeError(p.error));
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          // A restored purchase already acknowledged is one the server already has.
          if (p.status == PurchaseStatus.restored && !p.pendingCompletePurchase) continue;
          // No token means nothing to verify; end the wait rather than hang on it.
          if (p.verificationData.serverVerificationData.isEmpty) {
            if (waitedOn) _finish(_failed(null));
            continue;
          }
          // Read before the await: [_finish] for another event may clear it meanwhile.
          final offerCode = waitedOn ? _pendingOfferCode : null;
          final refused = await verify(
            p.verificationData.serverVerificationData,
            offerCode: offerCode,
          );
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
    _pendingOfferCode = null;
    _waiting = null;
    if (waiting != null && !waiting.isCompleted) waiting.complete(result);
  }

  static PaymentResult _failed(String? message, [PaymentFailureReason? reason]) =>
      PaymentResult(PaymentOutcome.failed, message: message, reason: reason);

  /// Play's failure, as a reason the paywall words in the person's language. The code itself
  /// ("BillingResponse.developerError") goes to the log — it once went straight onto the screen.
  static PaymentResult _storeError(IAPError? error) {
    final code = error?.message ?? '';
    // Reaches logcat in release too: the store's code and its own debug text, nothing personal.
    debugPrint('store: purchase failed: $code (${error?.details ?? '-'})');
    return _failed(null, reasonForStoreCode(code));
  }

  /// Play's response codes, by what a person can do about them. Anything unrecognised — a code a
  /// later plugin adds — is the generic failure, never shown raw.
  @visibleForTesting
  static PaymentFailureReason reasonForStoreCode(String code) => switch (code.split('.').last) {
    'networkError' ||
    'serviceUnavailable' ||
    'serviceDisconnected' ||
    'serviceTimeout' => PaymentFailureReason.storeBusy,
    'billingUnavailable' || 'featureNotSupported' => PaymentFailureReason.storeUnavailable,
    'itemUnavailable' => PaymentFailureReason.productUnavailable,
    'itemAlreadyOwned' => PaymentFailureReason.alreadyOwned,
    _ => PaymentFailureReason.storeFailed,
  };

  /// Play: the base plan's own offer (no offer id) before any promotional offer on it — or, given
  /// [offerId] (D-265), exactly that offer and nothing else: falling back to the base price would
  /// charge someone more than the offer they were sent.
  /// App Store (no [basePlanId]): the product itself; the account token must be a UUID.
  static PurchaseParam? _param(
    List<ProductDetails> found,
    String? basePlanId,
    String accountToken, {
    String? offerId,
  }) {
    if (basePlanId == null) {
      final product = found.firstOrNull;
      return product == null
          ? null
          : PurchaseParam(productDetails: product, applicationUserName: accountToken);
    }
    final plans = found.whereType<GooglePlayProductDetails>().where(
      (d) => _basePlanOf(d) == basePlanId,
    );
    final offer = offerId != null
        ? plans.where((d) => _offerOf(d) == offerId).firstOrNull
        : plans.where((d) => _offerOf(d) == null).firstOrNull ?? plans.firstOrNull;
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
