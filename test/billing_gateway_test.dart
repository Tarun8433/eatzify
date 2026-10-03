import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_pro/domain/entities/billing.dart';
import 'package:health_pro/domain/repositories/payment_gateway.dart';
import 'package:health_pro/presentation/features/billing/billing_controller.dart';

import 'fakes.dart';

/// The money path (docs/11 §5). A gateway saying "done" activates nothing: only the verified
/// webhook does, so every branch here ends by asking the server again — or by saying nothing
/// happened.
void main() {
  BillingController controllerFor(FakeBillingRepository repo, {PaymentGateway? gateway}) =>
      BillingController(billing: repo, gateway: gateway);

  Future<void> buy(BillingController c) async {
    c.select('PRO', 1);
    await c.purchase();
  }

  test("should hand a real order to the gateway, in the server's mode", () async {
    final repo = FakeBillingRepository(paymentsMode: 'production');
    final gateway = FakePaymentGateway();
    final c = controllerFor(repo, gateway: gateway);

    await buy(c);

    expect(gateway.opened, hasLength(1));
    expect(gateway.opened.single.orderId, 'eatzify_test_1');
    expect(gateway.opened.single.sessionId, 'session_test_1');
    // The app must never pick sandbox vs production itself (rule 2).
    expect(gateway.opened.single.mode, 'production');
    // Nothing was unlocked locally; the stub shortcut was not taken.
    expect(c.stubUnlocked.value, isFalse);
    expect(repo.completed, isEmpty);
  });

  test('should not open a gateway for a stub order', () async {
    final repo = FakeBillingRepository();
    final gateway = FakePaymentGateway();
    final c = controllerFor(repo, gateway: gateway);

    await buy(c);

    expect(gateway.opened, isEmpty);
    expect(repo.completed, ['eatzify_test_1']);
    expect(c.stubUnlocked.value, isTrue);
  });

  test('should say so when a real order has nothing to open it', () async {
    final repo = FakeBillingRepository(paymentsMode: 'production');
    final c = controllerFor(repo);

    await buy(c);

    expect(c.gatewayUnavailable.value, isTrue);
    expect(c.buying.value, isFalse);
  });

  test("should show the gateway's words when it fails", () async {
    final repo = FakeBillingRepository(paymentsMode: 'production');
    final gateway = FakePaymentGateway(
      result: const PaymentResult(PaymentOutcome.failed, message: 'Card declined'),
    );
    final c = controllerFor(repo, gateway: gateway);

    await buy(c);

    expect(c.buyError.value, 'Card declined');
    expect(c.stubUnlocked.value, isFalse);
  });

  test('should say nothing when the person backs out', () async {
    final repo = FakeBillingRepository(paymentsMode: 'production');
    final gateway = FakePaymentGateway(result: const PaymentResult.cancelled());
    final c = controllerFor(repo, gateway: gateway);

    await buy(c);

    expect(c.buyError.value, isNull);
    expect(c.gatewayUnavailable.value, isFalse);
    expect(c.buying.value, isFalse);
  });

  group('Google Play (payments_mode: play)', () {
    FakeBillingRepository playRepo() => FakeBillingRepository(paymentsMode: 'play')
      ..subscriptionResult = const Right(
        SubscriptionState(tier: 'FREE', status: 'active', storeAccountToken: 'acct_1'),
      );

    test("should sell the server's base plan through the store, never Cashfree", () async {
      final repo = playRepo();
      final gateway = FakePaymentGateway();
      final store = FakeStoreGateway();
      final c = BillingController(billing: repo, gateway: gateway, store: store);
      await c.load();

      await buy(c);

      expect(store.bought.single, (productId: 'pro', basePlanId: 'p1m', accountToken: 'acct_1'));
      expect(repo.bought, isEmpty);
      expect(gateway.opened, isEmpty);
      // Anything the store still holds unconfirmed is re-sent once entitlements say Play.
      expect(store.resumed, isPositive);
    });

    test('should say checkout cannot open when this build has no store', () async {
      final c = BillingController(billing: playRepo());
      await c.load();

      await buy(c);

      expect(c.gatewayUnavailable.value, isTrue);
      expect(c.buying.value, isFalse);
    });

    test("should show the server's words when it refuses the purchase", () async {
      final store = FakeStoreGateway(
        result: const PaymentResult(PaymentOutcome.failed, message: 'Bought on another account.'),
      );
      final c = BillingController(billing: playRepo(), store: store);
      await c.load();

      await buy(c);

      expect(c.buyError.value, 'Bought on another account.');
    });
  });

  test('should sell the App Store product on an iPhone, with no base plan', () async {
    final repo = FakeBillingRepository(paymentsMode: 'app_store')
      ..subscriptionResult = const Right(
        SubscriptionState(tier: 'FREE', status: 'active', storeAccountToken: 'acct_1'),
      );
    final store = FakeStoreGateway();
    final c = BillingController(billing: repo, store: store);
    await c.load();

    await buy(c);

    expect(store.bought.single, (
      productId: 'eatzify.pro.p1m',
      basePlanId: null,
      accountToken: 'acct_1',
    ));
    expect(repo.bought, isEmpty);
  });

  test('should say checkout cannot open when the store fails without words', () async {
    final repo = FakeBillingRepository(paymentsMode: 'play')
      ..subscriptionResult = const Right(
        SubscriptionState(tier: 'FREE', status: 'active', storeAccountToken: 'acct_1'),
      );
    final store = FakeStoreGateway(result: const PaymentResult(PaymentOutcome.failed));
    final c = BillingController(billing: repo, store: store);
    await c.load();

    await buy(c);

    expect(c.gatewayUnavailable.value, isTrue);
    expect(c.buying.value, isFalse);
  });
}
