/// What the server says this account may use. docs/11 §4: entitlements are resolved SERVER-side —
/// the app renders them and never computes one (CLAUDE.md rule 3).
class Entitlements {
  const Entitlements({required this.tier, required this.status, this.paymentsMode = 'stub'});

  Entitlements.fromJson(Map<String, dynamic> json)
    : this(
        tier: json['tier']?.toString() ?? 'FREE',
        status: json['status']?.toString() ?? 'active',
        // Defaults to the mode that sells nothing. A build that cannot read the field must not
        // assume it can take money.
        paymentsMode: json['payments_mode']?.toString() ?? 'stub',
      );

  /// FREE / BASIC / PRO — the server's vocabulary, shown through l10n (rule 4).
  final String tier;
  final String status;

  /// `stub` · `sandbox` · `production` (docs/11, D-194). The paywall asks so it can tell the truth
  /// about whether this build can take a payment.
  final String paymentsMode;

  /// Whether a real gateway is behind the pay button.
  bool get canTakePayment => paymentsMode != 'stub';

  /// The one question the UI asks: is there anything to sell this person? A paid tier, in any
  /// status the server still honours, means the upgrade surfaces stay away (docs/11 §10 names
  /// "upgrade CTA while subscribed" as a shipped defect of the old build).
  bool get isFree => tier == 'FREE';
}

/// A started purchase, as `POST /billing/checkout` reports it (D-194).
///
/// Holding one grants nothing: docs/11 §5 makes a verified webhook the only thing that activates a
/// subscription, so this is a handle for the gateway and a record for support.
class CheckoutSession {
  const CheckoutSession({
    required this.orderId,
    required this.amountPaise,
    required this.tier,
    required this.mode,
    this.paymentSessionId,
  });

  CheckoutSession.fromJson(Map<String, dynamic> json)
    : this(
        orderId: json['order_id']?.toString() ?? '',
        amountPaise: int.tryParse(json['amount_paise']?.toString() ?? '') ?? 0,
        tier: json['tier']?.toString() ?? '',
        mode: json['mode']?.toString() ?? 'stub',
        paymentSessionId: json['payment_session_id']?.toString(),
      );

  final String orderId;
  final int amountPaise;
  final String tier;
  final String mode;

  /// What Cashfree's SDK needs to open checkout. Null in stub mode, where there is none to open.
  final String? paymentSessionId;

  bool get isStub => mode == 'stub';
}

/// One purchasable cell of the price matrix: a tier for a duration, in paise (rule: money is
/// integer paise, never rupees-as-decimal).
class TierPrice {
  const TierPrice({required this.tier, required this.months, required this.pricePaise});

  final String tier;
  final int months;
  final int pricePaise;
}

/// What `GET /billing/subscription` says about the plan someone holds (docs/09 §7).
///
/// Every field is the SERVER's answer. Nothing here is worked out on the phone: the tier, the
/// renewal date and whether the trial is still on offer are all decisions docs/11 makes server-side
/// (CLAUDE.md rule 3).
class SubscriptionState {
  const SubscriptionState({
    required this.tier,
    required this.status,
    this.endsAt,
    this.startsAt,
    this.autoRenew = false,
    this.requiresAfa = false,
    this.trialEndsAt,
    this.cancelledAt,
    this.trialAvailable = false,
  });

  SubscriptionState.fromJson(Map<String, dynamic> json)
    : this(
        tier: json['tier']?.toString() ?? 'FREE',
        status: json['status']?.toString() ?? 'active',
        endsAt: DateTime.tryParse(json['ends_at']?.toString() ?? '')?.toLocal(),
        startsAt: DateTime.tryParse(json['starts_at']?.toString() ?? '')?.toLocal(),
        autoRenew: json['auto_renew'] == true,
        requiresAfa: json['requires_afa'] == true,
        trialEndsAt: DateTime.tryParse(json['trial_ends_at']?.toString() ?? '')?.toLocal(),
        cancelledAt: DateTime.tryParse(json['cancelled_at']?.toString() ?? '')?.toLocal(),
        trialAvailable: json['trial_available'] == true,
      );

  final String tier;

  /// `trialing` · `active` · `past_due` · `grace` · `cancelled` · `expired` (docs/11 §5).
  final String status;

  /// The end of the period being paid for or trialed. Null on FREE, which never expires.
  final DateTime? endsAt;
  final DateTime? startsAt;

  /// Whether it renews when [endsAt] arrives.
  final bool autoRenew;

  /// docs/11 §8: above ₹15,000 the bank asks for approval on every debit, so the renewal is a
  /// prompt rather than something that happens quietly.
  final bool requiresAfa;

  final DateTime? trialEndsAt;
  final DateTime? cancelledAt;

  /// docs/11 §6: one free week per number, for life.
  final bool trialAvailable;

  bool get isFree => tier == 'FREE';
  bool get isTrial => status == 'trialing';

  /// Whether a payment is expected at [endsAt].
  bool get willRenew => autoRenew && !isFree;

  /// Whether the plan is running but will stop at the end of the period.
  bool get endsAfterPeriod => !isFree && !autoRenew;
}

/// docs/11 §7's arithmetic, as the server worked it out. Shown in full before anything is charged:
/// "opaque proration generates tickets".
class UpgradeQuote {
  const UpgradeQuote({
    required this.tier,
    required this.months,
    required this.pricePaise,
    required this.creditPaise,
    required this.amountDuePaise,
    this.remainingDays = 0,
    this.totalDays = 0,
  });

  UpgradeQuote.fromJson(Map<String, dynamic> json)
    : this(
        tier: json['tier']?.toString() ?? '',
        months: int.tryParse((json['duration']?.toString() ?? '').replaceAll('M', '')) ?? 0,
        pricePaise: (json['price_paise'] as num?)?.toInt() ?? 0,
        creditPaise:
            ((json['proration'] as Map<String, dynamic>?)?['credit_paise'] as num?)?.toInt() ?? 0,
        amountDuePaise:
            ((json['proration'] as Map<String, dynamic>?)?['amount_due_paise'] as num?)?.toInt() ??
            0,
        remainingDays:
            ((json['proration'] as Map<String, dynamic>?)?['remaining_days'] as num?)?.toInt() ?? 0,
        totalDays:
            ((json['proration'] as Map<String, dynamic>?)?['total_days'] as num?)?.toInt() ?? 0,
      );

  final String tier;
  final int months;
  final int pricePaise;

  /// What the unused part of the running plan is worth. Never more than [pricePaise] — an upgrade
  /// reduces what is owed and never hands money back.
  final int creditPaise;
  final int amountDuePaise;
  final int remainingDays;
  final int totalDays;

  /// Nothing left to pay: the credit covered the whole price.
  bool get isFree => amountDuePaise == 0;
}
