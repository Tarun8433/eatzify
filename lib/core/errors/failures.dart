/// Failure types the presentation layer can render. docs/14 §3.
///
/// CLAUDE.md rule 7: `userMessage` comes from the API and is the ONLY text shown to a user for a
/// server-side failure. We never write our own copy for a medical or safety message.
sealed class Failure {
  const Failure(this.userMessage);

  /// Server-supplied, already localised. Display verbatim.
  final String userMessage;
}

/// No connectivity. The one case where the client owns the copy, because the server never saw it.
class OfflineFailure extends Failure {
  const OfflineFailure(super.userMessage);
}

/// Any non-2xx the server explained. `code` is the machine-readable error code from docs/09 §2.
class ApiFailure extends Failure {
  const ApiFailure(super.userMessage, {required this.code, this.status});

  final String code;
  final int? status;

  /// docs/09: the app responds to this by showing the upgrade sheet, never by hiding the feature.
  bool get isEntitlementRequired => code == 'ENTITLEMENT_REQUIRED';
}

/// A gate from docs/05 §3 — pregnancy, ckd, and the rest. No plan exists and none should be shown.
class ClinicalGateFailure extends Failure {
  const ClinicalGateFailure(super.userMessage, {required this.gate});

  final String gate;
}

/// Something we did not anticipate. Never surfaces a stack trace or an exception string.
class UnexpectedFailure extends Failure {
  const UnexpectedFailure(super.userMessage);
}
