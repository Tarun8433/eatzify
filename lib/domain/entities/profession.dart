/// What someone says they do, asked once during onboarding.
///
/// **A self-declaration, never a credential.** Choosing `doctor` here grants nothing and proves
/// nothing — docs/12 §6 makes a verified partner "ID + qualification document on file", reviewed
/// by a human. This exists to decide whether to OFFER the partner route, and for nothing else.
///
/// It is deliberately not persisted either. docs/13 §4 says collect less, and a field that only
/// chooses which screen to show next has no reason to live in the profile: the record that
/// matters is the coach application, which is stored and reviewed.
enum Profession {
  /// The overwhelming majority. No partner offer.
  none,
  trainer,
  nutritionist,

  /// A doctor with a nutrition speciality. Still unverified, still offered the same route.
  doctor;

  /// Whether to offer the partner route after onboarding.
  bool get mayCoach => this != Profession.none;
}
