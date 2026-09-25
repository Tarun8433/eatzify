/// One invite this coach has sent and nobody has answered yet (docs/09 §6).
///
/// [name] and [photoUrl] are filled only when the number belongs to an account, so their presence
/// tells the coach that the number is registered — the very thing docs/09 §3 keeps the invite
/// endpoint itself from revealing. Carried here as a deliberate product decision; see
/// `docs/DECISIONS.md`. It changes what the coach is TOLD, never what they may read: no health
/// field travels with an invite, and only accepting creates a grant.
class SentInvite {
  const SentInvite({
    required this.id,
    required this.phoneE164,
    required this.scopes,
    required this.status,
    required this.expiresAt,
    required this.createdAt,
    this.name,
    this.photoUrl,
  });

  SentInvite.fromJson(Map<String, dynamic> json)
    : this(
        id: json['id']?.toString() ?? '',
        phoneE164: json['phone_e164']?.toString() ?? '',
        scopes: (json['scopes'] as List?)?.map((s) => s.toString()).toList() ?? const [],
        status: json['status']?.toString() ?? 'pending',
        expiresAt: DateTime.tryParse(json['expires_at']?.toString() ?? ''),
        createdAt: DateTime.tryParse(json['created_at']?.toString() ?? ''),
        name: json['name']?.toString(),
        photoUrl: json['photo_url']?.toString(),
      );

  final String id;

  /// The number the coach typed, in the form sign-in stores it. Shown back to them because it is
  /// the only thing they are certain to recognise when no name is known.
  final String phoneE164;

  final List<String> scopes;
  final String status;
  final DateTime? expiresAt;
  final DateTime? createdAt;

  /// Null when the number is not on the app, or when the person has not given a name yet. Null is
  /// shown as the number rather than a placeholder — a made-up name would be a claim about
  /// somebody who may not exist here.
  final String? name;
  final String? photoUrl;
}
