import 'package:health_pro/domain/entities/onboarding_enums.dart';

/// The `POST /profile/onboarding` request body (docs/09 §4), built from controller state.
///
/// Wire names come from each enum's `wire` — docs/03 §2 is the only source of legal values, so the
/// app never invents a string the server has to guess at.
class OnboardingSubmission {
  const OnboardingSubmission({
    required this.ageYears,
    required this.heightCm,
    required this.weightKg,
    required this.sexAtBirth,
    required this.goal,
    required this.activity,
    required this.foodPreference,
    required this.mealCount,
    required this.lifestyle,
    required this.budgetTier,
    required this.conditions,
    required this.allergies,
    required this.consentGranted,
    this.goalWeightKg,
    this.screenedSpecialDiet,
    this.screenedInsulinOrKidney,
    this.screenedEatingDisorder,
    this.name,
    this.goalDeclared,
    this.wakeTime,
    this.sleepTime,
    this.sleepHours,
    this.breakfastTime,
    this.lunchTime,
    this.midMorningTime,
    this.bedtimeSnackTime,
    this.eveningSnackTime,
    this.dinnerTime,
    this.foodDislikes,
    this.budgetMonthlyInr,
    this.medications,
    this.digestiveSymptoms = const {},
    this.injuries = const {},
    this.menstrualRegularity,
    this.pregnantOrBreastfeeding,
    this.heavyBleedingOrPain,
    this.hormonalMedication,
  });

  final int ageYears;
  final int heightCm;
  final double weightKg;
  final double? goalWeightKg;
  final SexAtBirth sexAtBirth;
  final Goal goal;
  final ActivityLevel activity;
  final FoodPreference foodPreference;
  final MealCount mealCount;
  final Lifestyle lifestyle;
  final BudgetTier budgetTier;
  final Set<Condition> conditions;
  final Set<FoodAllergy> allergies;
  final bool consentGranted;
  final bool? screenedSpecialDiet;
  final bool? screenedInsulinOrKidney;
  final bool? screenedEatingDisorder;

  final String? name;
  final GoalDeclared? goalDeclared;

  /// "HH:MM", 24-hour. A time of day is not an instant — storing one as a DateTime makes it drift
  /// with whatever date it was attached to.
  final String? wakeTime;
  final String? sleepTime;
  final double? sleepHours;
  final String? breakfastTime;
  final String? lunchTime;

  /// docs/04 §7's five-to-six pattern only. Null for three and four meals, because those
  /// patterns have no such occasion — a time for a meal nobody eats is not missing data.
  final String? midMorningTime;
  final String? bedtimeSnackTime;

  final String? eveningSnackTime;
  final String? dinnerTime;

  /// Dislikes, never treated as allergies: an allergy is a hard exclusion, a dislike is a preference.
  final String? foodDislikes;

  /// Rupees a month (D-78). [budgetTier] is derived from it and is what the engine plans on.
  final int? budgetMonthlyInr;
  final String? medications;
  final Set<DigestiveSymptom> digestiveSymptoms;
  final Set<InjuryArea> injuries;

  /// FR-1.3 — female users only. Null for everyone else, and the server drops them regardless.
  final MenstrualRegularity? menstrualRegularity;
  final bool? pregnantOrBreastfeeding;
  final bool? heavyBleedingOrPain;
  final bool? hormonalMedication;

  Map<String, dynamic> toJson() => {
    'profile': {
      'age_years': ageYears,
      'height_cm': heightCm,
      'weight_kg': weightKg,
      if (goalWeightKg != null) 'goal_weight_kg': goalWeightKg,
      'sex_at_birth': sexAtBirth.wire,
      'goal': goal.wire,
      'activity': activity.wire,
      'food_preference': foodPreference.wire,
      'meal_count': mealCount.wire,
      'lifestyle': lifestyle.wire,
      'budget_tier': budgetTier.wire,
      if (budgetMonthlyInr != null) 'budget_monthly_inr': budgetMonthlyInr,
      if (name != null && name!.isNotEmpty) 'name': name,
      if (goalDeclared != null) 'goal_declared': goalDeclared!.wire,
      if (wakeTime != null) 'wake_time': wakeTime,
      if (sleepTime != null) 'sleep_time': sleepTime,
      if (sleepHours != null) 'sleep_hours': sleepHours,
      if (breakfastTime != null) 'breakfast_time': breakfastTime,
      if (lunchTime != null) 'lunch_time': lunchTime,
      if (midMorningTime != null) 'mid_morning_time': midMorningTime,
      if (bedtimeSnackTime != null) 'bedtime_snack_time': bedtimeSnackTime,
      if (eveningSnackTime != null) 'evening_snack_time': eveningSnackTime,
      if (dinnerTime != null) 'dinner_time': dinnerTime,
      if (foodDislikes != null && foodDislikes!.isNotEmpty) 'food_dislikes': foodDislikes,
    },
    'health_profile': {
      'conditions': conditions.map((c) => c.wire).toList(),
      'allergies': allergies.map((a) => a.wire).toList(),
      if (screenedSpecialDiet != null) 'screened_special_diet': screenedSpecialDiet,
      if (screenedInsulinOrKidney != null) 'screened_insulin_or_kidney': screenedInsulinOrKidney,
      if (screenedEatingDisorder != null) 'screened_eating_disorder': screenedEatingDisorder,
      if (medications != null && medications!.isNotEmpty) 'medications': medications,
      if (digestiveSymptoms.isNotEmpty)
        'digestive_symptoms': digestiveSymptoms.map((d) => d.wire).toList(),
      if (injuries.isNotEmpty) 'injuries': injuries.map((i) => i.wire).toList(),
      if (menstrualRegularity != null) 'menstrual_regularity': menstrualRegularity!.wire,
      if (pregnantOrBreastfeeding != null) 'pregnant_or_breastfeeding': pregnantOrBreastfeeding,
      if (heavyBleedingOrPain != null) 'heavy_bleeding_or_pain': heavyBleedingOrPain,
      if (hormonalMedication != null) 'hormonal_medication': hormonalMedication,
    },
    // FR-1.7: itemised, and storage consent is the one the server refuses without.
    'consents': [
      {'type': 'health_data_storage', 'granted': consentGranted},
    ],
  };

  /// docs/13: never log a health field. Conditions and allergies are health data.
  @override
  String toString() => 'OnboardingSubmission(ageYears: $ageYears, redacted)';
}

/// `201` from `POST /profile/onboarding`.
class OnboardingResult {
  const OnboardingResult({
    required this.userId,
    required this.healthProfileVersion,
    required this.gates,
  });

  final String userId;
  final int healthProfileVersion;

  /// docs/05 §3. Non-empty means no plan will be generated; the app shows the referral screen.
  final List<String> gates;

  bool get isGated => gates.isNotEmpty;
}
