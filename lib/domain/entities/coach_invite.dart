/// A coach asking to work with this client, as the server reports it (docs/09 §6).
///
/// An invite is a REQUEST and nothing more. It creates no access on its own: the scopes here are
/// what the coach is ASKING for, and only the client accepting turns any of it into a grant
/// (docs/10 §1 — "the level does not grant access. The consent grant does"). So this entity never
/// appears in the same list as a DataAccess row: one is a question, the other is an answer already
/// given, and showing them together would let a person revoke something they never agreed to.
class CoachInvite {
  const CoachInvite({
    required this.id,
    required this.coachUserId,
    required this.scopes,
    required this.status,
    required this.expiresAt,
    required this.coachVerified,
    required this.coachVerifiedAttributes,
    required this.whatVerificationMeans,
    this.coachName,
    this.coachPhotoUrl,
    this.coachDiscipline,
  });

  CoachInvite.fromJson(Map<String, dynamic> json)
    : this(
        id: json['id']?.toString() ?? '',
        coachUserId: (json['coach_user_id'] as num?)?.toInt() ?? 0,
        scopes: (json['scopes'] as List?)?.map((s) => s.toString()).toList() ?? const [],
        status: json['status']?.toString() ?? 'pending',
        expiresAt: DateTime.tryParse(json['expires_at']?.toString() ?? ''),
        coachName: json['coach_name']?.toString(),
        coachPhotoUrl: json['coach_photo_url']?.toString(),
        coachDiscipline: json['coach_discipline']?.toString(),
        coachVerified: json['coach_verified'] as bool? ?? false,
        coachVerifiedAttributes:
            (json['coach_verified_attributes'] as List?)?.map((a) => a.toString()).toList() ??
            const [],
        whatVerificationMeans: json['what_verification_means']?.toString() ?? '',
      );

  /// The server's id, a string — it goes straight back in `POST /coach/invites/{id}/accept`.
  final String id;

  final int coachUserId;

  /// Wire values (`basic`, `progress`, …). Shown through l10n, never raw (rule 4).
  final List<String> scopes;

  /// `pending` is the only status this list ever carries: the server filters the rest out.
  final String status;

  final DateTime? expiresAt;

  /// Who is asking. A person cannot consent to "Partner #25" — naming the coach is what makes the
  /// decision a decision. Null only when the account has no name yet.
  final String? coachName;
  final String? coachPhotoUrl;

  /// What the coach SAYS they do, self-declared. Shown through l10n, never raw (rule 4).
  final String? coachDiscipline;

  /// Whether a human reviewed them. Level 2 is an admin decision (docs/09 §9), never a claim the
  /// app makes on its own.
  final bool coachVerified;

  /// What a human actually confirmed (docs/02 FR-8.3). Empty for an unreviewed applicant.
  final List<String> coachVerifiedAttributes;

  /// docs/12 §6: publish exactly what verification means, wherever the badge appears.
  /// Server-authored (rule 7), so the app can show it beside a badge without paraphrasing it into
  /// an accreditation claim Eatzify does not make.
  final String whatVerificationMeans;
}
