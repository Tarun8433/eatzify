import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:health_pro/data/datasources/remote/in_app_store_gateway.dart';
import 'package:health_pro/domain/repositories/payment_gateway.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/billing_client_wrappers.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';

/// Stands in for the store plugin: one product on offer, and a stream the test pushes events into.
class _FakeStore implements InAppPurchase {
  final StreamController<List<PurchaseDetails>> events = StreamController.broadcast();
  int launches = 0;

  /// What Play would list for the product. Null keeps the one plain product above.
  List<ProductDetails>? catalogue;

  /// The param the last purchase sheet was opened with — which offer was asked for.
  PurchaseParam? lastParam;

  @override
  Stream<List<PurchaseDetails>> get purchaseStream => events.stream;

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<ProductDetailsResponse> queryProductDetails(Set<String> identifiers) async =>
      ProductDetailsResponse(
        productDetails:
            catalogue ??
            [
              ProductDetails(
                id: identifiers.first,
                title: 'Pro',
                description: '',
                price: '₹649',
                rawPrice: 649,
                currencyCode: 'INR',
              ),
            ],
        notFoundIDs: const [],
      );

  @override
  Future<bool> buyNonConsumable({required PurchaseParam purchaseParam}) async {
    launches++;
    lastParam = purchaseParam;
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// What Play sends when the purchase sheet is closed, or fails, before any purchase exists: one
/// event with no product id at all (in_app_purchase_android 0.5.3). A failure carries Play's
/// response code as its message, e.g. "BillingResponse.developerError".
PurchaseDetails _anonymous(PurchaseStatus status, {String? code}) =>
    PurchaseDetails(
        purchaseID: '',
        productID: '',
        status: status,
        transactionDate: null,
        verificationData: PurchaseVerificationData(
          localVerificationData: '',
          serverVerificationData: '',
          source: 'google_play',
        ),
      )
      ..error = code == null
          ? null
          : IAPError(source: 'google_play', code: 'purchase_error', message: code);

PricingPhaseWrapper _phase(String price) => PricingPhaseWrapper(
  billingCycleCount: 1,
  billingPeriod: 'P3M',
  formattedPrice: price,
  priceAmountMicros: 0,
  priceCurrencyCode: 'INR',
  recurrenceMode: RecurrenceMode.infiniteRecurring,
);

SubscriptionOfferDetailsWrapper _plan(String basePlanId, String? offerId, String price) =>
    SubscriptionOfferDetailsWrapper(
      basePlanId: basePlanId,
      offerId: offerId,
      offerTags: const [],
      offerIdToken: '$basePlanId/${offerId ?? 'base'}',
      pricingPhases: [_phase(price)],
    );

/// `pro` as Play lists it: one entry per offer, base plans first as Play returns them.
List<ProductDetails> _proCatalogue() => GooglePlayProductDetails.fromProductDetails(
  ProductDetailsWrapper(
    description: '',
    name: 'Pro',
    productId: 'pro',
    productType: ProductType.subs,
    title: 'Pro',
    subscriptionOfferDetails: [
      _plan('p1m', null, '₹649'),
      _plan('p3m', 'intro-week', '₹99'),
      _plan('p3m', null, '₹1,799'),
      _plan('p3m', 'personal-399', '₹399'),
    ],
  ),
);

String? _offerToken(PurchaseParam? param) =>
    (param?.productDetails as GooglePlayProductDetails?)?.offerToken;

/// A completed Play purchase of `pro`, with a token to verify.
PurchaseDetails _purchased() => PurchaseDetails(
  purchaseID: 'GPA.1',
  productID: 'pro',
  status: PurchaseStatus.purchased,
  transactionDate: null,
  verificationData: PurchaseVerificationData(
    localVerificationData: '',
    serverVerificationData: 'token-1',
    source: 'google_play',
  ),
);

void main() {
  late _FakeStore store;
  late InAppStoreGateway gateway;

  setUp(() {
    store = _FakeStore();
    gateway = InAppStoreGateway(verify: (_, {offerCode}) async => null, iap: store);
  });

  Future<PaymentResult> buy(String productId) =>
      gateway.buy(productId: productId, basePlanId: null, accountToken: 'acct');

  /// The bug: the cancel carried no product id, so it matched nothing, the purchase never finished,
  /// and the paywall sat on "Please wait…" with every other plan unreachable.
  test('should end the purchase when the sheet is closed without buying', () async {
    final first = buy('eatzify_basic');
    await pumpEventQueue();
    store.events.add([_anonymous(PurchaseStatus.canceled)]);

    expect((await first).outcome, PaymentOutcome.cancelled);
  });

  test('should let another plan be bought after a cancel', () async {
    final first = buy('eatzify_basic');
    await pumpEventQueue();
    store.events.add([_anonymous(PurchaseStatus.canceled)]);
    await first;

    final second = buy('eatzify_premium');
    await pumpEventQueue();

    expect(store.launches, 2, reason: 'the second plan opened its own purchase sheet');
    store.events.add([_anonymous(PurchaseStatus.canceled)]);
    expect((await second).outcome, PaymentOutcome.cancelled);
  });

  test('should end the purchase with a failure when Play errors before any purchase', () async {
    final first = buy('eatzify_basic');
    await pumpEventQueue();
    store.events.add([_anonymous(PurchaseStatus.error)]);

    expect((await first).outcome, PaymentOutcome.failed);
  });

  test('should ignore a nameless event when no purchase is waiting', () async {
    store.events.add([_anonymous(PurchaseStatus.canceled)]);
    await pumpEventQueue();

    final first = buy('eatzify_basic');
    await pumpEventQueue();
    store.events.add([_anonymous(PurchaseStatus.canceled)]);
    expect((await first).outcome, PaymentOutcome.cancelled);
  });

  /// The bug: Play's own code ("BillingResponse.developerError") was put on the paywall as the
  /// error. Every code becomes a reason the paywall words in the person's language; the code
  /// itself never reaches the screen.
  group("Play's error codes", () {
    Future<PaymentResult> failWith(String code) async {
      final first = buy('eatzify_basic');
      await pumpEventQueue();
      store.events.add([_anonymous(PurchaseStatus.error, code: code)]);
      return first;
    }

    for (final (code, reason) in [
      ('BillingResponse.developerError', PaymentFailureReason.storeFailed),
      ('BillingResponse.error', PaymentFailureReason.storeFailed),
      ('BillingResponse.networkError', PaymentFailureReason.storeBusy),
      ('BillingResponse.serviceUnavailable', PaymentFailureReason.storeBusy),
      ('BillingResponse.serviceDisconnected', PaymentFailureReason.storeBusy),
      ('BillingResponse.serviceTimeout', PaymentFailureReason.storeBusy),
      ('BillingResponse.billingUnavailable', PaymentFailureReason.storeUnavailable),
      ('BillingResponse.featureNotSupported', PaymentFailureReason.storeUnavailable),
      ('BillingResponse.itemUnavailable', PaymentFailureReason.productUnavailable),
      ('BillingResponse.itemAlreadyOwned', PaymentFailureReason.alreadyOwned),
      ('something new from a later plugin', PaymentFailureReason.storeFailed),
    ]) {
      test('should turn $code into a reason, never show it', () async {
        final result = await failWith(code);

        expect(result.outcome, PaymentOutcome.failed);
        expect(result.reason, reason);
        expect(result.message, isNull, reason: 'the raw code must not reach the paywall');
      });
    }
  });

  /// D-265: a personal offer is bought as exactly that Play offer, never quietly at full price.
  group('Play offers', () {
    Future<PaymentResult> buyPro({String? offerId}) async {
      store.catalogue = _proCatalogue();
      final result = gateway.buy(
        productId: 'pro',
        basePlanId: 'p3m',
        accountToken: 'acct',
        offerId: offerId,
      );
      await pumpEventQueue();
      store.events.add([_anonymous(PurchaseStatus.canceled)]);
      return result;
    }

    test('should open the sheet on the offer named by its offer id', () async {
      await buyPro(offerId: 'personal-399');

      expect(_offerToken(store.lastParam), 'p3m/personal-399');
    });

    test('should keep buying the base plan when no offer id is given', () async {
      await buyPro();

      expect(_offerToken(store.lastParam), 'p3m/base', reason: 'the base offer, not the intro');
    });

    test('should refuse rather than sell full price when Play has no such offer', () async {
      final result = await buyPro(offerId: 'gone');

      expect(result.outcome, PaymentOutcome.failed);
      expect(result.reason, PaymentFailureReason.productUnavailable);
      expect(store.launches, 0);
    });

    test("should read Play's price for the offer", () async {
      store.catalogue = _proCatalogue();

      final price = await gateway.offerPrice(
        productId: 'pro',
        basePlanId: 'p3m',
        offerId: 'personal-399',
      );

      expect(price, '₹399');
    });

    test('should hand the offer code to verify for the purchase it came with', () async {
      final codes = <String?>[];
      final verifying = InAppStoreGateway(
        verify: (_, {offerCode}) async {
          codes.add(offerCode);
          return null;
        },
        iap: store,
      );
      store.catalogue = _proCatalogue();

      final result = verifying.buy(
        productId: 'pro',
        basePlanId: 'p3m',
        accountToken: 'acct',
        offerId: 'personal-399',
        offerCode: 'Ab3_dE-f9GhIjKlMnOpQrS',
      );
      await pumpEventQueue();
      store.events.add([_purchased()]);

      expect((await result).outcome, PaymentOutcome.submitted);
      // Two listeners share the fake's stream: the gateway from setUp has no purchase waiting, so
      // it verifies without a code; the one that bought the offer sends it.
      expect(codes, contains('Ab3_dE-f9GhIjKlMnOpQrS'));
    });
  });
}
