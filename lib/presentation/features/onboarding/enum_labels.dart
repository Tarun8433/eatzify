import 'package:flutter/material.dart';
import 'package:health_pro/domain/entities/measurement.dart';
import 'package:health_pro/domain/entities/onboarding_enums.dart';
import 'package:health_pro/domain/usecases/validate_onboarding.dart';
import 'package:health_pro/presentation/l10n/app_localizations.dart';

/// The single place a domain enum becomes user-visible text.
///
/// CLAUDE.md rule 4 and docs/15's first audit finding: the old build rendered `lose_weight`,
/// `moderate` and `vegetarian` straight onto the profile screen. Every enum crosses into the UI
/// through here, so there is exactly one place to check that it never happens again.
extension SexAtBirthLabel on SexAtBirth {
  String label(AppLocalizations l) => switch (this) {
    SexAtBirth.male => l.sexMale,
    SexAtBirth.female => l.sexFemale,
    SexAtBirth.intersexPreferNotSay => l.sexIntersexPreferNotSay,
  };
}

extension GoalLabel on Goal {
  String label(AppLocalizations l) => switch (this) {
    Goal.fatLoss => l.goalFatLoss,
    Goal.muscleGain => l.goalMuscleGain,
    Goal.maintenance => l.goalMaintenance,
  };
}

/// The seven the user picks from. [GoalLabel] is the engine's three and is still used wherever a
/// stored plan reports what it was built for.
extension GoalDeclaredLabel on GoalDeclared {
  String label(AppLocalizations l) => switch (this) {
    GoalDeclared.weightLoss => l.goalDeclaredWeightLoss,
    GoalDeclared.weightGain => l.goalDeclaredWeightGain,
    GoalDeclared.fatLoss => l.goalDeclaredFatLoss,
    GoalDeclared.muscleGain => l.goalDeclaredMuscleGain,
    GoalDeclared.generalFitness => l.goalDeclaredGeneralFitness,
    GoalDeclared.medicalSupport => l.goalDeclaredMedicalSupport,
    GoalDeclared.other => l.goalDeclaredOther,
  };
}

extension DigestiveSymptomLabel on DigestiveSymptom {
  String label(AppLocalizations l) => switch (this) {
    DigestiveSymptom.none => l.digestiveNone,
    DigestiveSymptom.gas => l.digestiveGas,
    DigestiveSymptom.acidity => l.digestiveAcidity,
    DigestiveSymptom.bloating => l.digestiveBloating,
    DigestiveSymptom.constipation => l.digestiveConstipation,
    DigestiveSymptom.looseMotion => l.digestiveLooseMotion,
    DigestiveSymptom.ibs => l.digestiveIbs,
  };
}

extension InjuryAreaLabel on InjuryArea {
  String label(AppLocalizations l) => switch (this) {
    InjuryArea.none => l.injuryNone,
    InjuryArea.backPain => l.injuryBackPain,
    InjuryArea.kneePain => l.injuryKneePain,
    InjuryArea.jointPain => l.injuryJointPain,
    InjuryArea.otherInjury => l.injuryOther,
  };
}

extension MenstrualRegularityLabel on MenstrualRegularity {
  String label(AppLocalizations l) => switch (this) {
    MenstrualRegularity.regular => l.menstrualRegular,
    MenstrualRegularity.irregular => l.menstrualIrregular,
    MenstrualRegularity.notApplicable => l.menstrualNotApplicable,
  };
}

extension ActivityLevelLabel on ActivityLevel {
  String label(AppLocalizations l) => switch (this) {
    ActivityLevel.sedentary => l.activitySedentary,
    ActivityLevel.light => l.activityLight,
    ActivityLevel.moderate => l.activityModerate,
    ActivityLevel.heavy => l.activityHeavy,
  };

  /// docs/04 §3 ships a user-facing description per tier. Showing it is what stops people
  /// over-reporting, which is the largest error term in the whole calculation.
  String description(AppLocalizations l) => switch (this) {
    ActivityLevel.sedentary => l.activitySedentaryDesc,
    ActivityLevel.light => l.activityLightDesc,
    ActivityLevel.moderate => l.activityModerateDesc,
    ActivityLevel.heavy => l.activityHeavyDesc,
  };
}

extension ConditionLabel on Condition {
  String label(AppLocalizations l) => switch (this) {
    Condition.none => l.conditionNone,
    Condition.type2Diabetes => l.conditionType2Diabetes,
    Condition.prediabetes => l.conditionPrediabetes,
    Condition.hypertension => l.conditionHypertension,
    Condition.hypothyroid => l.conditionHypothyroid,
    Condition.hyperthyroid => l.conditionHyperthyroid,
    Condition.pcos => l.conditionPcos,
    Condition.postSurgery => l.conditionPostSurgery,
    Condition.ckd => l.conditionCkd,
    Condition.pregnancy => l.conditionPregnancy,
    Condition.lactation => l.conditionLactation,
    Condition.highCholesterol => l.conditionHighCholesterol,
    Condition.fattyLiver => l.conditionFattyLiver,
    Condition.heartProblem => l.conditionHeartProblem,
    Condition.digestiveIssue => l.conditionDigestiveIssue,
    Condition.otherDeclared => l.conditionOtherDeclared,
  };
}

extension FoodPreferenceLabel on FoodPreference {
  String label(AppLocalizations l) => switch (this) {
    FoodPreference.veg => l.preferenceVeg,
    FoodPreference.nonVeg => l.preferenceNonVeg,
    FoodPreference.eggetarian => l.preferenceEggetarian,
    FoodPreference.jain => l.preferenceJain,
    FoodPreference.vegan => l.preferenceVegan,
  };
}

extension FoodAllergyLabel on FoodAllergy {
  String label(AppLocalizations l) => switch (this) {
    FoodAllergy.milk => l.allergyMilk,
    FoodAllergy.wheatGluten => l.allergyWheatGluten,
    FoodAllergy.soy => l.allergySoy,
    FoodAllergy.peanut => l.allergyPeanut,
    FoodAllergy.treeNut => l.allergyTreeNut,
    FoodAllergy.egg => l.allergyEgg,
    FoodAllergy.fish => l.allergyFish,
    FoodAllergy.shellfish => l.allergyShellfish,
    FoodAllergy.sesame => l.allergySesame,
    FoodAllergy.mustard => l.allergyMustard,
    FoodAllergy.other => l.allergyOther,
  };
}

extension BudgetTierLabel on BudgetTier {
  String label(AppLocalizations l) => switch (this) {
    BudgetTier.low => l.budgetLow,
    BudgetTier.medium => l.budgetMedium,
    BudgetTier.premium => l.budgetPremium,
  };
}

extension LifestyleLabel on Lifestyle {
  String label(AppLocalizations l) => switch (this) {
    Lifestyle.office => l.lifestyleOffice,
    Lifestyle.student => l.lifestyleStudent,
    Lifestyle.nightShift => l.lifestyleNightShift,
    Lifestyle.flexible => l.lifestyleFlexible,
    Lifestyle.home => l.lifestyleHome,
  };
}

extension MealCountLabel on MealCount {
  String label(AppLocalizations l) => switch (this) {
    MealCount.three => l.mealCountThree,
    MealCount.four => l.mealCountFour,
    MealCount.fiveOrSix => l.mealCountFiveOrSix,
  };
}

extension OnboardingRejectLabel on OnboardingReject {
  String label(AppLocalizations l) => switch (this) {
    OnboardingReject.ageBelowMinimum => l.rejectAgeBelowMinimum,
    OnboardingReject.ageOutOfRange => l.rejectAgeOutOfRange,
    OnboardingReject.heightOutOfRange => l.rejectHeightOutOfRange,
    OnboardingReject.weightOutOfRange => l.rejectWeightOutOfRange,
    OnboardingReject.goalWeightBelowHealthyBmi => l.rejectGoalWeightBelowHealthyBmi,
    OnboardingReject.conditionNoneNotExclusive => l.rejectConditionNoneNotExclusive,
    OnboardingReject.consentNotGiven => l.rejectConsentNotGiven,
  };
}

/// `GET /profile` returns docs/03 §2 wire strings, not enums. These put them back through the same
/// label extensions above so there is still exactly one path from a domain value to visible text.
/// An unrecognised value returns null and the caller shows nothing rather than a raw string.
T? enumFromWire<T>(List<T> values, String wire, String Function(T) wireOf) {
  for (final v in values) {
    if (wireOf(v) == wire) return v;
  }
  return null;
}

/// Rule 4: a source is never rendered raw. Rule 10 requires it to be visible wherever the number
/// is, which means it needs words a person would use — "apple_health" is a wire value, not a label.
extension MeasurementSourceLabel on MeasurementSource {
  String label(AppLocalizations l) => switch (this) {
    MeasurementSource.manual => l.sourceManual,
    MeasurementSource.appleHealth => l.sourceAppleHealth,
    MeasurementSource.healthConnect => l.sourceHealthConnect,
  };
}

/// Icons for the option lists (D-104). Decoration beside a label that already carries the meaning —
/// a colour-blind or screen-reader user loses nothing — but it is what stops six white rows reading
/// as one block of text.
extension SexAtBirthIcon on SexAtBirth {
  IconData get icon => switch (this) {
    SexAtBirth.male => Icons.man,
    SexAtBirth.female => Icons.woman,
    SexAtBirth.intersexPreferNotSay => Icons.person_outline,
  };
}

extension GoalDeclaredIcon on GoalDeclared {
  IconData get icon => switch (this) {
    GoalDeclared.weightLoss => Icons.trending_down,
    GoalDeclared.weightGain => Icons.trending_up,
    GoalDeclared.fatLoss => Icons.monitor_weight_outlined,
    GoalDeclared.muscleGain => Icons.fitness_center,
    GoalDeclared.generalFitness => Icons.favorite_outline,
    GoalDeclared.medicalSupport => Icons.medical_services_outlined,
    GoalDeclared.other => Icons.more_horiz,
  };
}

extension ActivityLevelIcon on ActivityLevel {
  IconData get icon => switch (this) {
    ActivityLevel.sedentary => Icons.chair_outlined,
    ActivityLevel.light => Icons.directions_walk,
    ActivityLevel.moderate => Icons.directions_run,
    ActivityLevel.heavy => Icons.local_fire_department_outlined,
  };
}

/// A distinct glyph per condition (D-110).
///
/// Decoration, exactly as D-104 defined it: the LABEL carries the meaning, and every one of these
/// is excluded from semantics. What they buy is a list of sixteen rows the eye can move through
/// without reading all of them — which is what earns rows their scroll back after D-88 rejected it.
///
/// Material has no thyroid and no kidney, so some are metaphors rather than organs: a filter for
/// the kidneys, a slow gauge and a bolt for the two thyroid states. That is the right trade for a
/// mark that means nothing on its own — a wrong-looking organ would be read as a claim, a filter
/// icon beside the words "Kidney disease" is read as a bullet.
///
/// `none` deliberately has none. It is not a condition, and leaving its row without a disc is what
/// separates "none of these" from the list it opts out of.
extension ConditionIcon on Condition {
  IconData? get icon => switch (this) {
    Condition.none => null,
    Condition.type2Diabetes => Icons.water_drop_outlined,
    Condition.prediabetes => Icons.trending_up,
    Condition.hypertension => Icons.monitor_heart_outlined,
    Condition.hypothyroid => Icons.speed_outlined,
    Condition.hyperthyroid => Icons.bolt_outlined,
    Condition.pcos => Icons.female_outlined,
    Condition.postSurgery => Icons.healing_outlined,
    Condition.ckd => Icons.filter_alt_outlined,
    Condition.pregnancy => Icons.pregnant_woman_outlined,
    Condition.lactation => Icons.child_care_outlined,
    Condition.highCholesterol => Icons.bloodtype_outlined,
    Condition.fattyLiver => Icons.opacity_outlined,
    Condition.heartProblem => Icons.favorite_outline,
    Condition.digestiveIssue => Icons.restaurant_outlined,
    Condition.otherDeclared => Icons.more_horiz,
  };
}

/// Glyphs for the two multi-select lists on the health step (D-111). Same contract as
/// [ConditionIcon]: decoration, excluded from semantics, distinct so the eye can move down the
/// column without reading every row. `none` has none, because it is not one of them.
extension DigestiveSymptomIcon on DigestiveSymptom {
  IconData? get icon => switch (this) {
    DigestiveSymptom.none => null,
    DigestiveSymptom.gas => Icons.bubble_chart_outlined,
    DigestiveSymptom.acidity => Icons.local_fire_department_outlined,
    DigestiveSymptom.bloating => Icons.circle_outlined,
    DigestiveSymptom.constipation => Icons.hourglass_bottom,
    DigestiveSymptom.looseMotion => Icons.water_drop_outlined,
    DigestiveSymptom.ibs => Icons.sync_problem_outlined,
  };
}

extension InjuryAreaIcon on InjuryArea {
  IconData? get icon => switch (this) {
    InjuryArea.none => null,
    InjuryArea.backPain => Icons.airline_seat_recline_normal_outlined,
    InjuryArea.kneePain => Icons.directions_walk_outlined,
    InjuryArea.jointPain => Icons.accessibility_new_outlined,
    InjuryArea.otherInjury => Icons.more_horiz,
  };
}

/// Glyphs and one-line descriptions for the diet options (D-112).
///
/// The label alone made five near-identical rows: "Eggetarian" and "Jain" are not words every user
/// knows, and "Vegetarian" means different things to different people. The description is the part
/// that answers "is that me?" — it is content, not decoration, and unlike the icons it is read.
extension FoodPreferenceIcon on FoodPreference {
  IconData get icon => switch (this) {
    FoodPreference.veg => Icons.eco_outlined,
    FoodPreference.nonVeg => Icons.set_meal_outlined,
    FoodPreference.eggetarian => Icons.egg_outlined,
    FoodPreference.jain => Icons.spa_outlined,
    FoodPreference.vegan => Icons.grass_outlined,
  };

  String description(AppLocalizations l) => switch (this) {
    FoodPreference.veg => l.dietVegDesc,
    FoodPreference.nonVeg => l.dietNonVegDesc,
    FoodPreference.eggetarian => l.dietEggetarianDesc,
    FoodPreference.jain => l.dietJainDesc,
    FoodPreference.vegan => l.dietVeganDesc,
  };
}

/// Glyphs for the allergy grid (D-112). Decoration, excluded from semantics — but on a grid of
/// two-word labels they are what stops the six cells reading as one block of text.
extension FoodAllergyIcon on FoodAllergy {
  IconData get icon => switch (this) {
    FoodAllergy.milk => Icons.local_drink_outlined,
    FoodAllergy.wheatGluten => Icons.grass_outlined,
    FoodAllergy.soy => Icons.spa_outlined,
    FoodAllergy.peanut => Icons.scatter_plot_outlined,
    FoodAllergy.treeNut => Icons.park_outlined,
    FoodAllergy.egg => Icons.egg_outlined,
    FoodAllergy.fish => Icons.set_meal_outlined,
    FoodAllergy.shellfish => Icons.waves_outlined,
    FoodAllergy.sesame => Icons.grain_outlined,
    FoodAllergy.mustard => Icons.local_florist_outlined,
    FoodAllergy.other => Icons.more_horiz,
  };
}

/// Glyphs and descriptions for the routine step (D-113).
///
/// The three meal counts were "3 meals", "4 meals", "5-6 meals" and nothing else — a number is not
/// a day, and a user picking between them was guessing at what the app would do with each. The
/// description says what the day looks like; the glyph tells the rows apart.
extension MealCountIcon on MealCount {
  IconData get icon => switch (this) {
    MealCount.three => Icons.restaurant_outlined,
    MealCount.four => Icons.bakery_dining_outlined,
    MealCount.fiveOrSix => Icons.lunch_dining_outlined,
  };

  String description(AppLocalizations l) => switch (this) {
    MealCount.three => l.mealsThreeDesc,
    MealCount.four => l.mealsFourDesc,
    MealCount.fiveOrSix => l.mealsFiveSixDesc,
  };
}

extension LifestyleIcon on Lifestyle {
  IconData get icon => switch (this) {
    Lifestyle.office => Icons.work_outline,
    Lifestyle.student => Icons.school_outlined,
    Lifestyle.nightShift => Icons.nightlight_outlined,
    Lifestyle.flexible => Icons.swap_horiz_outlined,
    Lifestyle.home => Icons.home_outlined,
  };

  String description(AppLocalizations l) => switch (this) {
    Lifestyle.office => l.lifestyleOfficeDesc,
    Lifestyle.student => l.lifestyleStudentDesc,
    Lifestyle.nightShift => l.lifestyleNightShiftDesc,
    Lifestyle.flexible => l.lifestyleFlexibleDesc,
    Lifestyle.home => l.lifestyleHomeDesc,
  };
}
