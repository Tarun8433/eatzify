import 'dart:math';

import 'package:dartz/dartz.dart';
import 'package:get/get.dart';
import 'package:health_pro/core/errors/failures.dart';
import 'package:health_pro/core/widgets/view_state.dart';
import 'package:health_pro/domain/entities/billing.dart';
import 'package:health_pro/domain/repositories/billing_repository.dart';

/// The subscription screen (docs/14 §6, docs/11 §5–§9): what the person holds, and the four things
/// they can do about it — start the free week, cancel the renewal, move up a tier, or leave it be.
///
/// Every answer comes back from the server. This controller never works out a tier, a date or a
/// price (CLAUDE.md rule 3); when something changes it re-reads the state rather than patching it.
class SubscriptionController extends GetxController {
  SubscriptionController({required this.billing});

  final BillingRepository billing;

  final state = Rx<ViewState<SubscriptionState>>(const Loading());

  /// An action is running. The buttons wait rather than stack.
  final busy = false.obs;

  /// The server's `user_message` from the last refused action (rule 7). Null once it is shown.
  final error = RxnString();

  /// Set when an upgrade was settled outright — the credit covered the whole price, so there was
  /// nothing to pay and nothing to open.
  final upgraded = false.obs;

  @override
  void onInit() {
    super.onInit();
    load();
  }

  Future<void> load({bool quiet = false}) async {
    if (!quiet) state.value = const Loading();
    final result = await billing.subscription();
    state.value = result.fold(Failed.new, Ready.new);
  }

  /// docs/11 §6. The server decides whether this number may still have the week.
  Future<void> startTrial(String tier) => _act(() => billing.startTrial(tier));

  /// docs/09 §7: stops the renewal; the access already paid for stays.
  Future<void> cancelRenewal({String? reason}) => _act(() => billing.cancelRenewal(reason: reason));

  /// docs/11 §7's arithmetic, for the sheet that shows it before anything is charged.
  Future<UpgradeQuote?> quote({required String tier, required int months}) async {
    busy.value = true;
    error.value = null;
    final result = await billing.upgradeQuote(tier: tier, months: months);
    busy.value = false;
    return result.fold((f) {
      error.value = f.userMessage;
      return null;
    }, (quote) => quote);
  }

  /// Charges the difference the quote named.
  ///
  /// Returns true when the plan has already changed — either the credit covered everything, or
  /// this is a stub build where the activation the webhook would drive is run directly. Otherwise
  /// the order is open at the gateway and the screen says so.
  Future<bool> confirmUpgrade({required String tier, required int months}) async {
    if (busy.value) return false;
    busy.value = true;
    error.value = null;
    upgraded.value = false;

    // One key per attempt, so a retry below the app opens one order rather than two.
    final key = '${DateTime.now().microsecondsSinceEpoch}-${Random().nextInt(1 << 32)}';
    final started = await billing.upgrade(tier: tier, months: months, idempotencyKey: key);

    final session = started.fold<CheckoutSession?>((f) {
      error.value = f.userMessage;
      return null;
    }, (s) => s);

    if (session == null) {
      busy.value = false;
      return false;
    }

    // Nothing to pay: the server settled the order itself.
    var settled = session.amountPaise == 0;
    if (!settled && session.isStub) {
      final done = await billing.completeStubPayment(session.orderId);
      settled = done.fold((f) {
        error.value = f.userMessage;
        return false;
      }, (_) => true);
    }

    if (settled) await load(quiet: true);
    busy.value = false;
    upgraded.value = settled;
    return settled;
  }

  Future<void> _act(Future<Either<Failure, SubscriptionState>> Function() run) async {
    if (busy.value) return;
    busy.value = true;
    error.value = null;

    final result = await run();
    result.fold((f) => error.value = f.userMessage, (fresh) => state.value = Ready(fresh));
    busy.value = false;
  }
}
