/// What a partner says they do, on the application a human actually reviews.
///
/// Related to `Profession` but deliberately not the same list. Onboarding's question has a `none`
/// because most people answering it are not professionals, and it is asked only to decide whether
/// to OFFER the partner route — it is never stored. This one has an `other` because everybody
/// answering it has already said they are a professional, and a closed list with no escape hatch
/// gets answered wrongly rather than not at all.
///
/// **Self-declared, and never a credential.** Picking `doctor` grants nothing: docs/12 §6 makes a
/// verified partner "ID + qualification document on file", reviewed by a person, and what that
/// person confirmed lives in a separate column precisely so the gap between the two stays visible.
enum CoachDiscipline {
  trainer('trainer'),
  nutritionist('nutritionist'),
  doctor('doctor'),
  other('other');

  const CoachDiscipline(this.wire);

  /// The snake_case value the API stores. Never rendered (rule 4).
  final String wire;

  /// Null for an applicant who has not answered, and for any value a newer server sends that this
  /// build does not know — shown as the question rather than as a wrong answer.
  static CoachDiscipline? fromWire(String? wire) {
    for (final d in CoachDiscipline.values) {
      if (d.wire == wire) return d;
    }
    return null;
  }
}
