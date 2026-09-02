import 'package:health_pro/domain/entities/onboarding_enums.dart';

/// Onboarding validation. docs/02 FR-1, bounds from docs/03 §2.
///
/// This lives in the domain layer, never in a widget (CLAUDE.md rule 2). It is a *client-side
/// courtesy*: it gives immediate feedback and keeps obviously-bad data off the wire. The server
/// re-validates every one of these rules and the server's answer wins — docs/05 floors and gates are
/// enforced server-side on every path, and an app build is not a trustworthy enforcement point.
abstract final class OnboardingRules {
  // docs/03 §2
  static const minAge = 18;
  static const maxAge = 99;
  static const minHeightCm = 120;
  static const maxHeightCm = 220;
  static const minWeightKg = 30.0;
  static const maxWeightKg = 250.0;

  /// docs/05 §2 — a goal weight implying this or below is refused outright, no override.
  static const minGoalBmi = 18.5;

  /// The top of the healthy band, used ONLY to describe a weight range back to the user (D-76).
  /// Nothing rejects on it: a goal weight above this is a perfectly reasonable thing to want.
  static const maxHealthyBmi = 24.9;

  /// FR-1.3: this question is asked of women in this band, and only this band.
  static const pregnancyQuestionMinAge = 18;
  static const pregnancyQuestionMaxAge = 50;

  /// Outside this band we ask for confirmation before accepting (FR-1.4).
  static const plausibleHeightCm = (min: 140, max: 200);
  static const plausibleWeightKg = (min: 35.0, max: 160.0);
}

/// Why a field was rejected. The UI maps these to l10n strings — no copy lives here.
enum OnboardingReject {
  ageBelowMinimum,
  ageOutOfRange,
  heightOutOfRange,
  weightOutOfRange,
  goalWeightBelowHealthyBmi,
  conditionNoneNotExclusive,
  consentNotGiven,
}

/// A field-level outcome. `confirmNeeded` means plausible-but-unusual: accept after the user
/// confirms, per FR-1.4. It is not an error.
typedef FieldCheck = ({OnboardingReject? reject, bool confirmNeeded});

const FieldCheck _ok = (reject: null, confirmNeeded: false);

abstract final class ValidateOnboarding {
  /// FR-1.2: under 18 is refused, and the message must be plain and non-punitive.
  /// docs/05 §3 lists age < 18 as a hard block — the engine is never called at all.
  static FieldCheck age(int years) {
    if (years < OnboardingRules.minAge) {
      return (reject: OnboardingReject.ageBelowMinimum, confirmNeeded: false);
    }
    if (years > OnboardingRules.maxAge) {
      return (reject: OnboardingReject.ageOutOfRange, confirmNeeded: false);
    }
    return _ok;
  }

  /// FR-1.4: hard range, plus a confirm step on plausible outliers.
  static FieldCheck heightCm(int cm) {
    if (cm < OnboardingRules.minHeightCm || cm > OnboardingRules.maxHeightCm) {
      return (reject: OnboardingReject.heightOutOfRange, confirmNeeded: false);
    }
    const p = OnboardingRules.plausibleHeightCm;
    return (reject: null, confirmNeeded: cm < p.min || cm > p.max);
  }

  static FieldCheck weightKg(double kg) {
    if (kg < OnboardingRules.minWeightKg || kg > OnboardingRules.maxWeightKg) {
      return (reject: OnboardingReject.weightOutOfRange, confirmNeeded: false);
    }
    const p = OnboardingRules.plausibleWeightKg;
    return (reject: null, confirmNeeded: kg < p.min || kg > p.max);
  }

  /// FR-1.5 / docs/05 §5: a goal weight implying BMI < 18.5 is rejected at input with a plain
  /// explanation. **No override.** This is the one place the app computes a BMI, and it does so only
  /// to refuse — never to display a target, a status or a projection.
  static FieldCheck goalWeightKg(double goalKg, {required int heightCm}) {
    final heightM = heightCm / 100;
    final bmi = goalKg / (heightM * heightM);
    if (bmi < OnboardingRules.minGoalBmi) {
      return (reject: OnboardingReject.goalWeightBelowHealthyBmi, confirmNeeded: false);
    }
    return _ok;
  }

  /// The weight band that sits inside the healthy BMI range for a height (D-76).
  ///
  /// Derived from the SAME bound `goalWeightKg` rejects on, so the range shown and the range
  /// enforced can never disagree. It describes the input rule rather than prescribing a target:
  /// the user picks their own number and any value at or above the floor is accepted.
  static ({double low, double high}) healthyWeightRangeKg(int heightCm) {
    final heightM = heightCm / 100;
    final square = heightM * heightM;
    return (low: OnboardingRules.minGoalBmi * square, high: OnboardingRules.maxHealthyBmi * square);
  }

  /// Body mass index for a weight and height.
  ///
  /// Deliberately returns the number and nothing else — no band, no label, no colour. docs/05 §6
  /// forbids a judgemental status ("Obese" was on the old build's profile screen), and a bare
  /// figure beside a range is the version of this that informs without scoring anybody.
  static double bmiFor({required double weightKg, required int heightCm}) {
    final heightM = heightCm / 100;
    return weightKg / (heightM * heightM);
  }

  /// docs/03 §2: `none` is exclusive. Selecting it clears the rest.
  static FieldCheck conditions(Set<Condition> selected) {
    if (selected.isEmpty) return _ok;
    if (selected.contains(Condition.none) && selected.length > 1) {
      return (reject: OnboardingReject.conditionNoneNotExclusive, confirmNeeded: false);
    }
    return _ok;
  }

  /// Applies the exclusivity rule rather than reporting it — what a toggle should call.
  static Set<Condition> toggleCondition(Set<Condition> current, Condition tapped) {
    if (tapped == Condition.none) {
      return current.contains(Condition.none) ? <Condition>{} : {Condition.none};
    }
    final next = {...current, tapped}..remove(Condition.none);
    if (current.contains(tapped)) next.remove(tapped);
    return next;
  }

  /// FR-1.3: ask pregnancy/lactation status of women aged 18–50, and nobody else. Asking outside
  /// that band collects a health field with no clinical purpose, which docs/13 forbids.
  static bool shouldAskPregnancyStatus({required SexAtBirth sex, required int ageYears}) {
    return sex == SexAtBirth.female &&
        ageYears >= OnboardingRules.pregnancyQuestionMinAge &&
        ageYears <= OnboardingRules.pregnancyQuestionMaxAge;
  }

  /// docs/05 §3. Any of these means no plan is generated and the referral screen is shown.
  static Set<Condition> blockingGates(Set<Condition> selected) =>
      selected.where((c) => c.isBlockingGate).toSet();

  /// FR-1.7: itemised consent must be given before any health field is stored.
  static FieldCheck consent({required bool granted}) =>
      granted ? _ok : (reject: OnboardingReject.consentNotGiven, confirmNeeded: false);
}
