/// One of the person's own payments, as `GET /billing/payments` lists it, and the refund it
/// allows (admin panel plan, Phase B). The server decides which; the app only shows the button.
enum RefundOption {
  /// Inside 7 days: refunded straight away.
  selfServe,

  /// Past 7 days: asked for, and someone in finance decides.
  request,

  /// Already asked for.
  requested,

  /// Nothing to refund.
  none,
}

class PaidOrder {
  const PaidOrder({
    required this.orderId,
    required this.amountPaise,
    required this.plan,
    required this.paidAt,
    required this.refunded,
    required this.refund,
  });

  PaidOrder.fromJson(Map<String, dynamic> json)
    : this(
        orderId: json['order_id']?.toString() ?? '',
        amountPaise: int.tryParse(json['amount_paise']?.toString() ?? '') ?? 0,
        plan: json['plan']?.toString() ?? '',
        paidAt: DateTime.tryParse(json['paid_at']?.toString() ?? '')?.toLocal(),
        refunded: json['status'] == 'refunded',
        refund: switch (json['refund']) {
          'self_serve' => RefundOption.selfServe,
          'request' => RefundOption.request,
          'requested' => RefundOption.requested,
          _ => RefundOption.none,
        },
      );

  final String orderId;
  final int amountPaise;

  /// `PRO 3M` — tier and length, mapped through l10n before display (rule 4).
  final String plan;
  final DateTime? paidAt;
  final bool refunded;
  final RefundOption refund;
}
