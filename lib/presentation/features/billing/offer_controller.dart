import 'dart:math';

import 'package:get/get.dart';
import 'package:health_pro/core/widgets/view_state.dart';
import 'package:health_pro/domain/entities/billing.dart';
import 'package:health_pro/domain/repositories/billing_repository.dart';
import 'package:health_pro/domain/repositories/payment_gateway.dart';
import 'package:health_pro/domain/repositories/store_gateway.dart';

/// D-265: one personal offer, from its link's code to a purchase.
///
/// The code is all the app holds. What the offer is, and whether it is still this person's to
/// take, is `GET /billing/offers/:code`; what it costs is the server's (Cashfree) or Play's (a Play
/// offer). As everywhere in billing, a finished checkout is a cue to re-read entitlements — never
/// proof of anything (rule 3).
class OfferController extends GetxController {
  OfferController({
    required this.code,
    required this.billing,
    this.gateway,
    this.store,
    this.onPurchased,
  });

  final String code;
  final BillingRepository billing;

  /// Cashfree's checkout. Absent in tests and in a build with no SDK linked.
  final PaymentGateway? gateway;

  /// Google Play, for a `play` offer. Absent off Android and in tests that are not about it.
  final StoreGateway? store;

  /// Re-reads what the account may use, after any checkout that may have moved money.
  final Future<void> Function()? onPurchased;

  /// Loading → Ready, or Failed with the server's `OFFER_NOT_FOUND` message. Never Empty: a missing
  /// offer is a 404, which is a failure with words of its own (rule 7).
  final state = Rx<ViewState<PersonalOffer>>(const Loading());

  /// Play's own price string for the offer, once the store has said. Null means "no figure".
  final storePrice = RxnString();

  /// A purchase in flight. Blocks the second tap and is reset on EVERY way out of [buy].
  final buying = false.obs;

  /// Whatever the server or the gateway refused with, verbatim (rule 7).
  final buyError = RxnString();

  /// Which store problem stopped the last purchase, worded by the sheet.
  final storeProblem = Rxn<PaymentFailureReason>();

  /// Nothing in this build can open the checkout the server started.
  final gatewayUnavailable = false.obs;

  PersonalOffer? get offer => switch (state.value) {
    Ready<PersonalOffer>(:final data) => data,
    _ => null,
  };

  Future<void> load() async {
    state.value = const Loading();
    final result = await billing.offer(code);
    result.fold((f) => state.value = Failed(f), (o) => state.value = Ready(o));

    final play = offer?.play;
    final store = this.store;
    if (play == null || store == null) return;
    storePrice.value = await store.offerPrice(
      productId: play.productId,
      basePlanId: play.basePlanId,
      offerId: play.offerId,
    );
  }

  /// Buys the offer. True when a checkout went through, so the sheet can close; false when it was
  /// cancelled, refused or could not start, with the reason in the fields above.
  Future<bool> buy() async {
    final offer = this.offer;
    if (offer == null || buying.value) return false;

    buying.value = true;
    buyError.value = null;
    storeProblem.value = null;
    gatewayUnavailable.value = false;
    // `finally`, not a reset per branch: the paywall's "Please wait…" stuck once because one exit
    // path forgot to reset it. Whatever happens below, the button comes back.
    try {
      final result = offer.isPlay ? await _payAtStore(offer) : await _payAtGateway(offer);
      return result != null && await _after(result);
    } finally {
      buying.value = false;
    }
  }

  /// Play: the offer by its ids, with the account token so no other account can claim it, and the
  /// code so the server can mark the offer used once Google confirms the purchase.
  Future<PaymentResult?> _payAtStore(PersonalOffer offer) async {
    final store = this.store;
    final play = offer.play;
    if (store == null || play == null) {
      gatewayUnavailable.value = true;
      return null;
    }

    final state = await billing.subscription();
    final accountToken = state.fold((f) {
      buyError.value = f.userMessage;
      return null;
    }, (s) => s.storeAccountToken);
    if (accountToken == null) {
      if (buyError.value == null) gatewayUnavailable.value = true;
      return null;
    }

    return store.buy(
      productId: play.productId,
      basePlanId: play.basePlanId,
      offerId: play.offerId,
      offerCode: offer.code,
      accountToken: accountToken,
    );
  }

  /// Cashfree: an order the SERVER prices from the offer, then the existing hosted checkout. A stub
  /// server has nothing to open, so the webhook's activation is simulated, as on the paywall.
  Future<PaymentResult?> _payAtGateway(PersonalOffer offer) async {
    // One key per attempt; the double tap is already blocked by [buying].
    final key = '${DateTime.now().microsecondsSinceEpoch}-${Random().nextInt(1 << 32)}';
    final started = await billing.offerCheckout(code: offer.code, idempotencyKey: key);
    final session = started.fold<CheckoutSession?>((f) {
      buyError.value = f.userMessage;
      return null;
    }, (s) => s);
    if (session == null) return null;

    if (session.isStub) {
      final done = await billing.completeStubPayment(session.orderId);
      return done.fold(
        (f) => PaymentResult(PaymentOutcome.failed, message: f.userMessage),
        (_) => const PaymentResult.submitted(),
      );
    }

    final gateway = this.gateway;
    final sessionId = session.paymentSessionId;
    if (gateway == null || sessionId == null || sessionId.isEmpty) {
      gatewayUnavailable.value = true;
      return null;
    }
    return gateway.open(orderId: session.orderId, paymentSessionId: sessionId, mode: session.mode);
  }

  Future<bool> _after(PaymentResult result) async {
    switch (result.outcome) {
      case PaymentOutcome.submitted:
        await onPurchased?.call();
        return true;
      case PaymentOutcome.cancelled:
        return false;
      case PaymentOutcome.failed:
        if (result.message case final message?) {
          buyError.value = message;
        } else if (result.reason case final reason?) {
          storeProblem.value = reason;
        } else {
          gatewayUnavailable.value = true;
        }
        // A failure after money may have moved (a refused verify) still re-reads the account.
        await onPurchased?.call();
        return false;
    }
  }
}
