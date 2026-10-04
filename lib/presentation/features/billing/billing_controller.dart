import 'dart:math';

import 'package:get/get.dart';
import 'package:health_pro/core/widgets/view_state.dart';
import 'package:health_pro/domain/entities/billing.dart';
import 'package:health_pro/domain/repositories/billing_repository.dart';
import 'package:health_pro/domain/repositories/payment_gateway.dart';
import 'package:health_pro/domain/repositories/store_gateway.dart';

/// What the server says this account may use, for the screens that sell the rest.
///
/// The default while loading — and on any failure — is NO premium surfaces: docs/11 §10 names
/// "upgrade CTA rendered while subscribed" as a shipped defect of the old build, and a network
/// blip must not flash a sales banner at a paying customer.
class BillingController extends GetxController {
  BillingController({required this.billing, this.gateway, this.store});

  final BillingRepository billing;

  /// Opens Cashfree's checkout for a real order. Absent in tests and on a build with no gateway
  /// linked, where a non-stub purchase says so rather than pretending to have opened one.
  final PaymentGateway? gateway;

  /// Google Play (Phase 4) or the App Store (Phase 5). Used only when the server says
  /// `payments_mode: play` or `app_store`.
  final StoreGateway? store;

  /// Store mode sells through the store's own sheet, where the server's offer codes do not apply.
  bool get isStoreBilling => entitlements.value?.isStoreBilling ?? false;

  final entitlements = Rxn<Entitlements>();

  /// The price matrix as one of the four states (rule 6). It was a bare list before, which left
  /// the paywall with no way to tell "still loading" from "the server refused" — both rendered as
  /// a spinner that never ended (D-160).
  final priceState = Rx<ViewState<List<TierPrice>>>(const Loading());

  /// The row the buy button would act on. One selection across BOTH cards, not one per card:
  /// somebody buys a tier for a duration, so two independent selections would only be a way to
  /// leave the sheet showing two answers to one question.
  final selectedTier = RxnString();
  final selectedMonths = RxnInt();

  /// Whether the small line under each price reads per month or per year. The prices are per TERM
  /// on the wire; both readings are derived from the same paise and neither is stored.
  final perYear = false.obs;

  /// True only once the server has SAID so.
  bool get showPremium => entitlements.value?.isFree ?? false;

  /// Whether a real gateway sits behind the pay button. Server-decided (D-194): a stub build must
  /// not draw one, and a live build must not keep saying payments are coming soon.
  bool get canTakePayment => entitlements.value?.canTakePayment ?? false;

  /// D-249: the server says this app may not take payment at all (iPhone until Apple in-app
  /// purchase, Android until Play approves User Choice Billing). No pay button is drawn.
  bool get paymentsUnavailable => entitlements.value?.paymentsUnavailable ?? false;

  /// The paise of the selected row, or null when nothing is selected. Read from the matrix the
  /// server sent — the app never computes a price (rule 2).
  int? get selectedPricePaise {
    final tier = selectedTier.value;
    final months = selectedMonths.value;
    if (tier == null || months == null) return null;

    for (final row in _rows) {
      if (row.tier == tier && row.months == months) return row.pricePaise;
    }
    return null;
  }

  /// A purchase in flight. Blocks the second tap; the idempotency key covers the network retry.
  final buying = false.obs;

  /// Whatever the server refused with, verbatim (rule 7).
  final buyError = RxnString();

  /// Set when a real order was started but nothing could open it — no gateway linked into this
  /// build, or a server that returned no session. The paywall says so in its own words (rule 5);
  /// a controller has no l10n.
  final gatewayUnavailable = false.obs;

  /// Which store problem stopped the last purchase, so the paywall can say it plainly.
  final storeProblem = Rxn<PaymentFailureReason>();

  /// Set once a stub purchase has unlocked the tier, so the sheet can say what it actually did
  /// rather than looking like a real payment went through.
  final stubUnlocked = false.obs;

  /// Buy the selected row.
  ///
  /// Takes no money by itself. On a real build the session id goes to Cashfree's SDK; on a stub
  /// build there is nothing to open, so the same activation the webhook would drive is run through
  /// the simulate route and the entitlements are re-read from the server — never assumed.
  /// D-236: what the user typed in the offer-code field. Priced by the SERVER at checkout —
  /// the app never computes a discount; a wrong code comes back as the server's user_message.
  final couponCode = ''.obs;

  Future<void> purchase() async {
    final tier = selectedTier.value;
    final months = selectedMonths.value;
    if (tier == null || months == null || buying.value) return;

    buying.value = true;
    buyError.value = null;
    gatewayUnavailable.value = false;
    storeProblem.value = null;

    if (isStoreBilling) {
      await _payAtStore(tier, months);
      buying.value = false;
      return;
    }

    // One key per attempt. A double tap is already blocked above; this is for the retry that
    // happens below the app, where the same request is sent twice and must open one order.
    final key = '${DateTime.now().microsecondsSinceEpoch}-${Random().nextInt(1 << 32)}';

    final coupon = couponCode.value.trim();
    final started = await billing.checkout(
      tier: tier,
      months: months,
      idempotencyKey: key,
      couponCode: coupon.isEmpty ? null : coupon,
    );

    final session = started.fold<CheckoutSession?>((f) {
      buyError.value = f.userMessage;
      return null;
    }, (s) => s);

    if (session == null) {
      buying.value = false;
      return;
    }

    if (session.isStub) {
      final done = await billing.completeStubPayment(session.orderId);
      done.fold((f) => buyError.value = f.userMessage, (_) {
        stubUnlocked.value = true;
      });
      // The tier comes back from the server, never from what the app just did (rule 3).
      await load();
      buying.value = false;
      return;
    }

    await _payAtGateway(session);
    buying.value = false;
  }

  /// Hands the server's session to Cashfree and waits for the person to come back.
  ///
  /// What returns from the gateway is NOT proof of payment: docs/11 §5 makes the verified webhook
  /// the only thing that activates a subscription. So a completed checkout is followed by asking
  /// the server what this account may use — never by unlocking anything here (rule 3).
  Future<void> _payAtGateway(CheckoutSession session) async {
    final sessionId = session.paymentSessionId;
    final gateway = this.gateway;
    if (gateway == null || sessionId == null || sessionId.isEmpty) {
      // A real order with nothing to open it: say so plainly rather than leave a dead button.
      gatewayUnavailable.value = true;
      return;
    }

    final result = await gateway.open(
      orderId: session.orderId,
      paymentSessionId: sessionId,
      mode: session.mode,
    );
    await _afterGateway(result);
  }

  /// Buys the row through the platform store. The token goes to the server, which re-reads it from the store
  /// before granting anything; the tier is then re-read, never assumed (rule 3).
  Future<void> _payAtStore(String tier, int months) async {
    final store = this.store;
    final product = entitlements.value?.storeProductFor(tier, months);
    if (store == null || product == null) {
      gatewayUnavailable.value = true;
      return;
    }

    // The account id Play stores with the purchase, so no other account can claim the token.
    final state = await billing.subscription();
    final accountToken = state.fold((f) {
      buyError.value = f.userMessage;
      return null;
    }, (s) => s.storeAccountToken);
    if (accountToken == null) {
      if (buyError.value == null) gatewayUnavailable.value = true;
      return;
    }

    final result = await store.buy(
      productId: product.productId,
      basePlanId: product.basePlanId,
      accountToken: accountToken,
    );
    await _afterGateway(result);
  }

  Future<void> _afterGateway(PaymentResult result) async {
    switch (result.outcome) {
      case PaymentOutcome.submitted:
        await load();
      case PaymentOutcome.cancelled:
        break;
      case PaymentOutcome.failed:
        // A failure with no words of its own (store unavailable, product not found) must still say
        // something — it used to set a null error and the button looked dead.
        if (result.reason != null && result.message == null) {
          storeProblem.value = result.reason;
        } else if (result.message == null) {
          gatewayUnavailable.value = true;
        } else {
          buyError.value = result.message;
        }
        await load();
    }
  }

  @override
  void onInit() {
    super.onInit();
    load();
  }

  Future<void> load() async {
    final result = await billing.entitlements();
    result.fold((_) => entitlements.value = null, (e) => entitlements.value = e);
    // A store purchase whose verify never landed (bad network, pending payment that cleared later).
    if (isStoreBilling) await store?.resumePending();
  }

  /// Fetched when the paywall opens, not before — the tab needs the tier, not the price matrix.
  /// [force] is the retry on the failed state, which must go back to the server rather than
  /// return the failure it is trying to clear.
  Future<void> loadPrices({bool force = false}) async {
    if (!force && priceState.value is Ready<List<TierPrice>>) return;
    priceState.value = const Loading();
    final result = await billing.prices();
    result.fold((f) => priceState.value = Failed(f), (rows) {
      priceState.value = rows.isEmpty ? const Empty() : Ready(rows);
      if (rows.isNotEmpty) select(rows.first.tier, rows.first.months);
    });
  }

  void select(String tier, int months) {
    selectedTier.value = tier;
    selectedMonths.value = months;
  }

  bool isSelected(String tier, int months) =>
      selectedTier.value == tier && selectedMonths.value == months;

  /// The tiers the server priced, in its own order. Derived rather than declared: a tier the
  /// backend stops selling should leave this sheet by disappearing from the response, not by
  /// needing a release (rule 3 — the server decides what is on sale).
  List<String> get tiers {
    final rows = _rows;
    final seen = <String>[];
    for (final row in rows) {
      if (!seen.contains(row.tier)) seen.add(row.tier);
    }
    return seen;
  }

  List<TierPrice> pricesFor(String tier) => _rows.where((r) => r.tier == tier).toList();

  List<TierPrice> get _rows => switch (priceState.value) {
    Ready<List<TierPrice>>(:final data) => data,
    _ => const [],
  };
}
