import 'package:health_pro/domain/entities/coach_discipline.dart';

/// A coach application, as the server reports it (docs/12 §6).
///
/// Two levels and one hard line between them. Level 1 is "signup + agreement" and needs no human;
/// level 2 is "ID + qualification document on file", where on file means somebody looked. The app
/// can carry an applicant to `submitted` and no further — nothing here ever claims verified.
class CoachApplication {
  const CoachApplication({
    required this.status,
    required this.level,
    required this.agreementAccepted,
    required this.hasIdDocument,
    required this.hasQualificationDocument,
    required this.whatVerificationMeans,
    this.discipline,
    this.rejectionReason,
    this.coachingAgreementAccepted = false,
  });

  CoachApplication.fromJson(Map<String, dynamic> json)
    : this(
        status: json['status']?.toString() ?? 'draft',
        discipline: CoachDiscipline.fromWire(json['discipline']?.toString()),
        level: (json['level'] as num?)?.toInt() ?? 1,
        agreementAccepted: json['agreement_accepted'] as bool? ?? false,
        hasIdDocument: json['has_id_document'] as bool? ?? false,
        hasQualificationDocument: json['has_qualification_document'] as bool? ?? false,
        whatVerificationMeans: json['what_verification_means']?.toString() ?? '',
        rejectionReason: json['rejection_reason']?.toString(),
        coachingAgreementAccepted: json['coaching_agreement_accepted'] as bool? ?? false,
      );

  /// `draft` · `submitted` · `verified` · `rejected`. Shown through l10n, never raw (rule 4).
  final String status;

  /// What the applicant SAYS they do. Null until they answer — onboarding asks the same question
  /// but throws the answer away (it only decides whether to offer this route), so this is the only
  /// copy of it that exists, the only one that can be read back, and the only one that can change.
  final CoachDiscipline? discipline;

  final int level;
  final bool agreementAccepted;

  /// Whether a document is on file — never its id. The server sends booleans on purpose: an id in
  /// a response is an id in a log.
  final bool hasIdDocument;
  final bool hasQualificationDocument;

  /// docs/12 §6: "publish exactly what verification means". Server-authored (rule 7), so the app
  /// can show it beside a badge without paraphrasing it into an accreditation claim.
  final String whatVerificationMeans;
  final String? rejectionReason;

  /// docs/12 §6's second agreement, which level 3 rests on alongside a client's grant (D-235).
  final bool coachingAgreementAccepted;

  /// Level 3 — the only level that may ask a client for chat (docs/10 §1).
  bool get isCoachingPartner => level >= 3;

  /// Verified, but not yet a Coaching Partner: the coaching agreement is the next step on offer.
  bool get canAcceptCoachingAgreement => isVerified && !coachingAgreementAccepted;

  bool get isWaitingForReview => status == 'submitted';
  bool get isVerified => status == 'verified';

  /// Both documents are required before a reviewer has anything to look at (docs/12 §6).
  bool get canSubmit => agreementAccepted && hasIdDocument && hasQualificationDocument;
}
