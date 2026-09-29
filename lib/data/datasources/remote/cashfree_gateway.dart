import 'dart:async';

import 'package:flutter_cashfree_pg_sdk/api/cferrorresponse/cferrorresponse.dart';
import 'package:flutter_cashfree_pg_sdk/api/cfpayment/cfwebcheckoutpayment.dart';
import 'package:flutter_cashfree_pg_sdk/api/cfpaymentgateway/cfpaymentgatewayservice.dart';
import 'package:flutter_cashfree_pg_sdk/api/cfsession/cfsession.dart';
import 'package:flutter_cashfree_pg_sdk/utils/cfenums.dart';
import 'package:flutter_cashfree_pg_sdk/utils/cfexceptions.dart';
import 'package:health_pro/domain/repositories/payment_gateway.dart';

/// Cashfree's hosted checkout, wrapped so the rest of the app never imports their SDK.
///
/// The SDK is callback-based and global — one pair of callbacks for the whole process — so this
/// registers them once and routes each answer to the order that is waiting. A callback for an
/// order nobody is waiting on is dropped rather than crossed with another purchase.
class CashfreeGateway implements PaymentGateway {
  CashfreeGateway({CFPaymentGatewayService? service})
    : _service = service ?? CFPaymentGatewayService() {
    _service.setCallback(_onVerify, _onError);
  }

  final CFPaymentGatewayService _service;

  /// The order currently on screen, and the future its caller is awaiting.
  String? _pending;
  Completer<PaymentResult>? _waiting;

  @override
  Future<PaymentResult> open({
    required String orderId,
    required String paymentSessionId,
    required String mode,
  }) async {
    // A second tap while checkout is up would leave the first caller waiting forever.
    if (_waiting != null && !_waiting!.isCompleted) {
      return const PaymentResult.cancelled();
    }

    final CFSession session;
    try {
      session = CFSessionBuilder()
          .setEnvironment(
            // The server's mode decides the host. Anything that is not production is treated as
            // the sandbox: a wrong guess towards LIVE would send test credentials at real money.
            mode == 'production' ? CFEnvironment.PRODUCTION : CFEnvironment.SANDBOX,
          )
          .setOrderId(orderId)
          .setPaymentSessionId(paymentSessionId)
          .build();
    } on CFException catch (e) {
      return PaymentResult(PaymentOutcome.failed, message: e.message);
    }

    final waiting = Completer<PaymentResult>();
    _pending = orderId;
    _waiting = waiting;

    try {
      final checkout = CFWebCheckoutPaymentBuilder().setSession(session).build();
      await _service.doPayment(checkout);
    } on CFException catch (e) {
      _pending = null;
      _waiting = null;
      return PaymentResult(PaymentOutcome.failed, message: e.message);
    }

    return waiting.future;
  }

  /// Cashfree's "the person finished" signal. It is NOT proof of payment — docs/11 §5: only the
  /// verified webhook activates anything, so the caller re-reads entitlements from the server.
  void _onVerify(String orderId) => _finish(orderId, const PaymentResult.submitted());

  void _onError(CFErrorResponse error, String orderId) =>
      _finish(orderId, PaymentResult(PaymentOutcome.failed, message: error.getMessage()));

  void _finish(String orderId, PaymentResult result) {
    final waiting = _waiting;
    if (waiting == null || waiting.isCompleted || _pending != orderId) return;
    _pending = null;
    _waiting = null;
    waiting.complete(result);
  }
}
