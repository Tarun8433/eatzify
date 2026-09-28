/// One coach's access to this client's data, as the server reports it (docs/10 §3).
///
/// The client's side of the consent grant. A paused row is still listed — what access USED to
/// exist is part of the answer, and a list that quietly forgets a revoked coach cannot be audited
/// by the person it belongs to.
class DataAccess {
  const DataAccess({
    required this.coachUserId,
    required this.scopes,
    required this.status,
    required this.expiresAt,
  });

  DataAccess.fromJson(Map<String, dynamic> json)
    : this(
        coachUserId: (json['coach_user_id'] as num?)?.toInt() ?? 0,
        scopes: (json['scopes'] as List?)?.map((s) => s.toString()).toList() ?? const [],
        status: json['status']?.toString() ?? 'paused',
        expiresAt: DateTime.tryParse(json['expires_at']?.toString() ?? ''),
      );

  final int coachUserId;

  /// Wire values (`basic`, `progress`, …). Shown through l10n, never raw (rule 4).
  final List<String> scopes;

  /// `active` or `paused`.
  final String status;
  final DateTime? expiresAt;

  bool get isActive => status == 'active';
}
