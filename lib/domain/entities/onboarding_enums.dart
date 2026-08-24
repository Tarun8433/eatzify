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

enum Goal {
  fatLoss('fat_loss'),
  muscleGain('muscle_gain'),
  maintenance('maintenance');

  const Goal(this.wire);
  final String wire;
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
  otherDeclared('other_declared');

  const Condition(this.wire);
  final String wire;

  /// docs/05 §3 BLOCK list. The engine refuses to plan; the app shows a referral screen.
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

enum BudgetTier {
  low('low'),
  medium('medium'),
  premium('premium');

  const BudgetTier(this.wire);
  final String wire;
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

enum MealCount {
  three('3'),
  four('4'),
  fiveOrSix('5_6');

  const MealCount(this.wire);
  final String wire;
}
