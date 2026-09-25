/// One of docs/13 §3's itemised consents, as it stands right now.
///
/// `type` is the server's key and is never rendered raw (rule 4) — the screen maps it through l10n.
class ConsentItem {
  const ConsentItem({
    required this.type,
    required this.granted,
    this.policyVersion = '1.0.0',
    this.decidedAt,
  });

  ConsentItem.fromJson(Map<String, dynamic> json)
    : this(
        type: json['type']?.toString() ?? '',
        granted: json['granted'] == true,
        policyVersion: json['policy_version']?.toString() ?? '1.0.0',
        decidedAt: DateTime.tryParse(json['decided_at']?.toString() ?? '')?.toLocal(),
      );

  /// `health_data_storage`, `plan_generation` or `marketing`.
  final String type;
  final bool granted;

  /// Which version of the notice they agreed to. "They agreed" is only evidence if it says to what.
  final String policyVersion;

  final DateTime? decidedAt;

  ConsentItem copyWith({bool? granted}) => ConsentItem(
    type: type,
    granted: granted ?? this.granted,
    policyVersion: policyVersion,
    decidedAt: decidedAt,
  );
}

/// An export or a deletion, and where it got to (docs/13 §9).
class PrivacyRequest {
  const PrivacyRequest({
    required this.id,
    required this.kind,
    required this.status,
    this.requestedAt,
    this.executeAfter,
    this.completedAt,
    this.downloadExpiresAt,
  });

  PrivacyRequest.fromJson(Map<String, dynamic> json)
    : this(
        id: json['id']?.toString() ?? '',
        kind: json['kind']?.toString() ?? '',
        status: json['status']?.toString() ?? '',
        requestedAt: DateTime.tryParse(json['requested_at']?.toString() ?? '')?.toLocal(),
        executeAfter: DateTime.tryParse(json['execute_after']?.toString() ?? '')?.toLocal(),
        completedAt: DateTime.tryParse(json['completed_at']?.toString() ?? '')?.toLocal(),
        downloadExpiresAt: DateTime.tryParse(
          json['download_expires_at']?.toString() ?? '',
        )?.toLocal(),
      );

  final String id;

  /// `export` or `delete`.
  final String kind;

  /// `pending`, `notified`, `done` or `cancelled`.
  final String status;

  final DateTime? requestedAt;

  /// When a deletion actually runs — seven days after it was asked for.
  final DateTime? executeAfter;

  final DateTime? completedAt;
  final DateTime? downloadExpiresAt;

  /// A deletion that has not run and has not been called off.
  bool get isDeletionPending => kind == 'delete' && (status == 'pending' || status == 'notified');
}

/// What the Privacy & data screen shows: the consents, and anything in flight.
typedef PrivacyState = ({List<ConsentItem> consents, List<PrivacyRequest> requests});
