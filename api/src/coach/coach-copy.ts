/// User-facing copy for coach onboarding.
///
/// CLAUDE.md rule 7: `user_message` is the only string the app renders, and it comes from here.
/// The wording in this file is not decoration — docs/12 §6 is explicit that Eatzify is not an
/// accrediting body (doc 00 §8) and that loose certification claims are a bad place to be under
/// the National Commission for Allied and Healthcare Professions Act framework.

/// docs/12 §6, near-verbatim: "Publish exactly what verification means."
///
/// Every screen that shows a partner badge has to be able to show this beside it. "Verified" here
/// means a document was seen, and nothing more.
export const WHAT_VERIFICATION_MEANS =
  "We have checked this partner's identity and have a copy of the qualification they " +
  'submitted. Eatzify does not certify or accredit practitioners.';

/// docs/12 §6: "call it 'Eatzify Verified Partner', not 'Eatzify Certified Coach'."
export const PARTNER_LEVEL_NAMES: Readonly<Record<number, string>> = {
  1: 'Affiliate Partner',
  2: 'Eatzify Verified Partner',
  3: 'Coaching Partner',
};

export const AGREEMENT_REQUIRED =
  'Please accept the partner agreement before continuing.';

export const DOCUMENTS_REQUIRED =
  'Add a photo ID and a qualification document, then submit for review.';

export const ALREADY_SUBMITTED =
  'Your application is with our team. We will let you know as soon as it has been reviewed.';

export const ALREADY_VERIFIED = 'You are already a verified partner.';

/// docs/12 §6: the coaching agreement is only offered to a partner who is already verified.
export const COACHING_NEEDS_VERIFICATION =
  'The coaching agreement opens once your documents have been verified.';
