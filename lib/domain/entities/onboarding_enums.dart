/// The onboarding input contract. docs/03 §2 — these are the ONLY legal values, and the wire names
/// are the snake_case ones the API expects.
///
/// CLAUDE.md rule 4: never render `wire` to a user. Every label goes through l10n.
library;

enum SexAtBirth {
  male('male'),
  female('female'),
  intersexPreferNotSay('intersex_prefer_not_say');

  const SexAtBirth(this.wire);
  final String wire;
}

/// What the ENGINE plans from. docs/04 defines calorie direction for exactly these three.
enum Goal {
  fatLoss('fat_loss'),
  muscleGain('muscle_gain'),
  maintenance('maintenance');

  const Goal(this.wire);
  final String wire;
}

/// What the USER picked, in their words. Seven options; the engine still only knows three.
///
/// These are deliberately not [Goal] values: the rule pack has no calorie or macro semantics for
/// "general fitness", and inventing one here would be the app computing a target (CLAUDE.md rule 2).
/// Both are sent — `goal` drives the plan, `goal_declared` is what a coach sees and what a later
/// rule pack can act on.
enum GoalDeclared {
  weightLoss('weight_loss', Goal.fatLoss),
  weightGain('weight_gain', Goal.muscleGain),
  fatLoss('fat_loss', Goal.fatLoss),
  muscleGain('muscle_gain', Goal.muscleGain),
  generalFitness('general_fitness', Goal.maintenance),
  medicalSupport('medical_support', Goal.maintenance),
  other('other', Goal.maintenance);

  const GoalDeclared(this.wire, this.engineGoal);
  final String wire;

  /// The [Goal] the engine plans from when this is chosen.
  ///
  /// `weightGain` maps to `muscleGain` because a surplus is the only direction the engine has —
  /// it is the closest honest answer, not an equivalence, and it is the first thing to revisit when
  /// the rule pack grows a lean-gain track.
  final Goal engineGoal;

  /// docs/05: picking a medical goal is a reason to ask the health questions carefully, never a
  /// reason to generate a plan the clinical gates would refuse.
  bool get impliesMedicalContext => this == GoalDeclared.medicalSupport;
}

enum ActivityLevel {
  sedentary('sedentary'),
  light('light'),
  moderate('moderate'),
  heavy('heavy');

  const ActivityLevel(this.wire);
  final String wire;
}

/// docs/03 §2. `none` is exclusive — selecting it clears the rest, enforced in the DTO and again here.
enum Condition {
  none('none'),
  type2Diabetes('type2_diabetes'),
  prediabetes('prediabetes'),
  hypertension('hypertension'),
  hypothyroid('hypothyroid'),
  hyperthyroid('hyperthyroid'),
  pcos('pcos'),
  postSurgery('post_surgery'),
  ckd('ckd'),
  pregnancy('pregnancy'),
  lactation('lactation'),
  highCholesterol('high_cholesterol'),
  fattyLiver('fatty_liver'),
  heartProblem('heart_problem'),
  digestiveIssue('digestive_issue'),
  otherDeclared('other_declared');

  const Condition(this.wire);
  final String wire;

  /// docs/05 §3 BLOCK list. The engine refuses to plan; the app shows a referral screen.
  ///
  /// `highCholesterol`, `fattyLiver`, `heartProblem` and `digestiveIssue` are deliberately NOT here.
  /// Whether a cardiac or hepatic condition should stop plan generation is a clinical decision that
  /// belongs in docs/05 with a dietitian's sign-off — not one the app invents. They are collected
  /// and stored; the gate classification is open (see DECISIONS.md).
  bool get isBlockingGate => const {
    Condition.ckd,
    Condition.pregnancy,
    Condition.lactation,
    Condition.hyperthyroid,
    Condition.postSurgery,
  }.contains(this);
}

/// docs/03 §2. Food allergies only — never environmental. FR-1.6: the old build collected
/// "Dust, pollution" in a diet app, which is clinically useless and a health-data liability.
enum FoodAllergy {
  milk('milk'),
  wheatGluten('wheat_gluten'),
  soy('soy'),
  peanut('peanut'),
  treeNut('tree_nut'),
  egg('egg'),
  fish('fish'),
  shellfish('shellfish'),
  sesame('sesame'),
  mustard('mustard'),
  other('other');

  const FoodAllergy(this.wire);
  final String wire;
}

enum FoodPreference {
  veg('veg'),
  nonVeg('non_veg'),
  eggetarian('eggetarian'),
  jain('jain'),
  vegan('vegan');

  const FoodPreference(this.wire);
  final String wire;
}

/// What the ENGINE plans from: the `cost:*` tags a food may carry (docs/03 §4).
enum BudgetTier {
  low('low'),
  medium('medium'),
  premium('premium');

  const BudgetTier(this.wire);
  final String wire;

  /// The tier a monthly food budget falls in (D-78).
  ///
  /// The user picks rupees on a slider; the engine only knows three tiers, so this is the one place
  /// the two vocabularies meet. Both are sent — the amount is what a coach sees and what a later
  /// rule pack could price against, the tier is what plans get built from.
  static BudgetTier forMonthlyInr(int rupees) {
    if (rupees < BudgetRange.mediumFromInr) return BudgetTier.low;
    if (rupees < BudgetRange.premiumFromInr) return BudgetTier.medium;
    return BudgetTier.premium;
  }
}

/// The monthly food budget slider (D-78). Rupees per month, for one person.
///
/// The bounds are the product's: ₹2,000 is about the least a month of home-cooked meals costs, and
/// ₹18,000 is where the tier stops changing anything — above it every food is already affordable,
/// so a longer slider would move a number without moving a plan.
abstract final class BudgetRange {
  static const minInr = 2000;
  static const maxInr = 18000;

  /// The slider moves in ₹500 steps. Finer than that is false precision on a figure nobody knows
  /// to the rupee, and it makes the handle fiddly on a small phone.
  static const stepInr = 500;

  /// Tier boundaries. Roughly thirds of the range, rounded to numbers a person would say out loud.
  static const mediumFromInr = 6000;
  static const premiumFromInr = 12000;

  static const defaultInr = 8000;

  static int clamp(int rupees) => rupees.clamp(minInr, maxInr);
}

enum Lifestyle {
  office('office'),
  student('student'),
  nightShift('night_shift'),
  flexible('flexible'),
  home('home');

  const Lifestyle(this.wire);
  final String wire;
}

/// Reported symptoms, not diagnoses — `Condition.digestiveIssue` is the diagnosed version.
/// `none` is exclusive, like conditions.
enum DigestiveSymptom {
  none('none'),
  gas('gas'),
  acidity('acidity'),
  bloating('bloating'),
  constipation('constipation'),
  looseMotion('loose_motion'),
  ibs('ibs');

  const DigestiveSymptom(this.wire);
  final String wire;
}

/// Musculoskeletal limits. They do not change a diet plan; they change what movement it is honest
/// to suggest alongside one. `none` is exclusive.
enum InjuryArea {
  none('none'),
  backPain('back_pain'),
  kneePain('knee_pain'),
  jointPain('joint_pain'),
  otherInjury('other_injury');

  const InjuryArea(this.wire);
  final String wire;
}

/// FR-1.3: asked of female users only.
enum MenstrualRegularity {
  regular('regular'),
  irregular('irregular'),
  notApplicable('not_applicable');

  const MenstrualRegularity(this.wire);
  final String wire;
}

enum MealCount {
  three('3'),
  four('4'),
  fiveOrSix('5_6');

  const MealCount(this.wire);
  final String wire;
}
