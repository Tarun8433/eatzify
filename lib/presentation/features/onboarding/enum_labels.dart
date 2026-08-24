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
