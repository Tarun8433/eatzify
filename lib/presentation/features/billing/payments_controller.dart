import 'package:dartz/dartz.dart';
import 'package:get/get.dart';
import 'package:health_pro/core/errors/failures.dart';
import 'package:health_pro/core/widgets/view_state.dart';
import 'package:health_pro/domain/entities/paid_order.dart';
import 'package:health_pro/domain/repositories/billing_repository.dart';

/// This account's payments and their refunds (admin panel plan, Phase B). Which refund a payment
/// allows is the server's answer, never worked out here (rule 2).
class PaymentsController extends GetxController {
  PaymentsController({required this.billing});

  final BillingRepository billing;

  final state = Rx<ViewState<List<PaidOrder>>>(const Loading());

  /// The payment a refund or request is in flight for.
  final busy = RxnString();

  /// The server's refusal, verbatim (rule 7).
  final error = RxnString();

  @override
  void onInit() {
    super.onInit();
    load();
  }

  Future<void> load() async {
    state.value = const Loading();
    final result = await billing.paidOrders();
    state.value = result.fold(Failed.new, (rows) => rows.isEmpty ? const Empty() : Ready(rows));
  }

  /// Inside 7 days. True when the refund went through.
  Future<bool> refund(PaidOrder order) => _act(order, () => billing.refund(order.orderId));

  /// Past 7 days. True when the request was sent.
  Future<bool> request(PaidOrder order, String reason) =>
      _act(order, () => billing.requestRefund(order.orderId, reason.trim()));

  Future<bool> _act(PaidOrder order, Future<Either<Failure, Unit>> Function() send) async {
    if (busy.value != null) return false;
    busy.value = order.orderId;
    error.value = null;
    final result = await send();
    busy.value = null;
    return result.fold(
      (f) {
        error.value = f.userMessage;
        return false;
      },
      (_) async {
        await load();
        return true;
      },
    );
  }
}
