/// How a started checkout ended, as the app is allowed to know it.
///
/// Deliberately coarse: docs/11 §5 makes a verified webhook the ONLY thing that activates a
/// subscription, so a gateway saying "done" is a cue to ask the server again — never a fact about
/// what the account may now use.
enum PaymentOutcome {
  /// The person completed the flow. The webhook decides whether money actually arrived.
  submitted,

  /// They backed out. Nothing was charged and nothing needs saying.
  cancelled,

  /// The gateway refused or broke. [PaymentResult.message] carries its words.
  failed,
}

/// Why a store purchase could not start, when the store gave no words of its own.
enum PaymentFailureReason {
  /// Google Play / App Store billing is not available on this phone (not installed from the store,
  /// or no store account signed in).
  storeUnavailable,

  /// The store does not sell this plan (missing or inactive in the store's console).
  productUnavailable,
}

class PaymentResult {
  const PaymentResult(this.outcome, {this.message, this.reason});

  const PaymentResult.submitted() : this(PaymentOutcome.submitted);
  const PaymentResult.cancelled() : this(PaymentOutcome.cancelled);

  final PaymentOutcome outcome;

  /// The gateway's own words, shown only when it failed. Never invented here.
  final String? message;

  /// Set when the store failed without words, so the app can say which of the two it was.
  final PaymentFailureReason? reason;
}

/// Opens the payment gateway for a started order.
///
/// An interface so the money path can be tested without a gateway, and so a build with no SDK
/// linked (or a stub server) has something honest to return.
// ignore: one_member_abstracts — a seam for the SDK, not a function in search of a class.
abstract class PaymentGateway {
  /// Opens checkout for [orderId] with the session the server started.
  ///
  /// [mode] is the server's, not the app's: `sandbox` and `production` talk to different Cashfree
  /// hosts, and the app must never decide which one it is (rule 2/3).
  Future<PaymentResult> open({
    required String orderId,
    required String paymentSessionId,
    required String mode,
  });
}
