import 'package:get/get.dart' hide Condition;
import 'package:health_pro/core/format/time_of_day_text.dart';
import 'package:health_pro/domain/entities/onboarding_enums.dart';
import 'package:health_pro/domain/entities/profile_view.dart';
import 'package:health_pro/domain/repositories/profile_repository.dart';

/// Backs both edit sheets. Sends only what actually changed — the server carries omitted fields
/// forward (D-33), so posting the whole object would risk overwriting a field the user never
/// touched with a stale value read at page load.
class EditProfileController extends GetxController {
  EditProfileController({required this.profiles, required ProfileView initial})
    : _initial = initial {
    goal.value = _wire(Goal.values, initial.goal, (e) => e.wire);
    activity.value = _wire(ActivityLevel.values, initial.activity, (e) => e.wire);
    diet.value = _wire(FoodPreference.values, initial.foodPreference, (e) => e.wire);
    weightKg.value = initial.weightKg;
    goalDeclared.value = _wire(GoalDeclared.values, initial.goalDeclared ?? '', (e) => e.wire);
    mealCount.value = _wire(MealCount.values, initial.mealCount, (e) => e.wire);
    lifestyle.value = _wire(Lifestyle.values, initial.lifestyle, (e) => e.wire);
    budgetMonthlyInr.value = BudgetRange.clamp(initial.budgetMonthlyInr ?? BudgetRange.defaultInr);
    menstrualRegularity.value = _wire(
      MenstrualRegularity.values,
      initial.menstrualRegularity ?? '',
      (e) => e.wire,
    );
    name.value = initial.name ?? '';
    ageYears.value = initial.ageYears;
    heightCm.value = initial.heightCm;
    goalWeightKg.value = initial.goalWeightKg;
    wakeTime.value = initial.wakeTime;
    sleepTime.value = initial.sleepTime;
    breakfastTime.value = initial.breakfastTime;
    lunchTime.value = initial.lunchTime;
    eveningSnackTime.value = initial.eveningSnackTime;
    dinnerTime.value = initial.dinnerTime;
    foodDislikes.value = initial.foodDislikes ?? '';
    medications.value = initial.medications ?? '';
    pregnantOrBreastfeeding.value = initial.pregnantOrBreastfeeding;
    heavyBleedingOrPain.value = initial.heavyBleedingOrPain;
    hormonalMedication.value = initial.hormonalMedication;
    digestiveSymptoms.assignAll(
      initial.digestiveSymptoms
          .map((w) => _wire(DigestiveSymptom.values, w, (e) => e.wire))
          .whereType<DigestiveSymptom>(),
    );
    injuries.assignAll(
      initial.injuries
          .map((w) => _wire(InjuryArea.values, w, (e) => e.wire))
          .whereType<InjuryArea>(),
    );
    conditions.assignAll(
      initial.conditions
          .map((w) => _wire(Condition.values, w, (e) => e.wire))
          .whereType<Condition>(),
    );
    allergies.assignAll(
      initial.allergies
          .map((w) => _wire(FoodAllergy.values, w, (e) => e.wire))
          .whereType<FoodAllergy>(),
    );
  }

  final ProfileRepository profiles;
  final ProfileView _initial;

  final goal = Rxn<Goal>();
  final activity = Rxn<ActivityLevel>();
  final diet = Rxn<FoodPreference>();
  final weightKg = RxnDouble();
  final conditions = <Condition>{}.obs;
  final allergies = <FoodAllergy>{}.obs;

  // The rest of what onboarding asked for. Missing here until D-72, which is why a user could not
  // change the very thing an error told them to change.
  final name = ''.obs;
  final ageYears = RxnInt();
  final heightCm = RxnInt();
  final goalWeightKg = RxnDouble();
  final goalDeclared = Rxn<GoalDeclared>();
  final mealCount = Rxn<MealCount>();
  final lifestyle = Rxn<Lifestyle>();

  /// Rupees a month (D-78); the tier is derived, never picked.
  final budgetMonthlyInr = BudgetRange.defaultInr.obs;

  BudgetTier get budgetTier => BudgetTier.forMonthlyInr(budgetMonthlyInr.value);
  final wakeTime = RxnString();
  final sleepTime = RxnString();

  /// Derived from the two clock times, exactly as in onboarding (D-77) — an edit must not be a way
  /// to store a duration that disagrees with the times beside it.
  double? get sleepHours =>
      TimeOfDayText.hoursSlept(bedtime: sleepTime.value, wakeTime: wakeTime.value);
  final breakfastTime = RxnString();
  final lunchTime = RxnString();
  final eveningSnackTime = RxnString();
  final dinnerTime = RxnString();
  final foodDislikes = ''.obs;
  final medications = ''.obs;
  final digestiveSymptoms = <DigestiveSymptom>{}.obs;
  final injuries = <InjuryArea>{}.obs;
  final menstrualRegularity = Rxn<MenstrualRegularity>();
  final pregnantOrBreastfeeding = Rxn<bool>();
  final heavyBleedingOrPain = Rxn<bool>();
  final hormonalMedication = Rxn<bool>();

  /// FR-1.3: the menstrual block is offered to female users only, exactly as in onboarding.
  bool get asksFemaleHealth => _initial.sexAtBirth == SexAtBirth.female.wire;

  final saving = false.obs;

  /// The server's `user_message`, verbatim (CLAUDE.md rule 7).
  final error = RxnString();

  static T? _wire<T>(List<T> values, String wire, String Function(T) wireOf) {
    for (final v in values) {
      if (wireOf(v) == wire) return v;
    }
    return null;
  }

  /// docs/03 §2: `none` is exclusive, same rule the onboarding flow applies.
  void toggleCondition(Condition tapped) {
    if (tapped == Condition.none) {
      conditions.assignAll(conditions.contains(Condition.none) ? {} : {Condition.none});
      return;
    }
    final next = {...conditions, tapped}..remove(Condition.none);
    if (conditions.contains(tapped)) next.remove(tapped);
    conditions.assignAll(next);
  }

  void toggleAllergy(FoodAllergy tapped) {
    final next = {...allergies};
    allergies.contains(tapped) ? next.remove(tapped) : next.add(tapped);
    allergies.assignAll(next);
  }

  void toggleDigestiveSymptom(DigestiveSymptom tapped) => digestiveSymptoms.assignAll(
    _toggleExclusive(digestiveSymptoms.toSet(), tapped, DigestiveSymptom.none),
  );

  void toggleInjury(InjuryArea tapped) =>
      injuries.assignAll(_toggleExclusive(injuries.toSet(), tapped, InjuryArea.none));

  /// `none` clears the rest and steps aside when something else is picked — the same rule
  /// onboarding applies, so an edit cannot store a combination onboarding would have refused.
  static Set<T> _toggleExclusive<T>(Set<T> current, T value, T noneValue) {
    if (current.contains(value)) return {...current}..remove(value);
    if (value == noneValue) return {noneValue};
    return {...current, value}..remove(noneValue);
  }

  Map<String, dynamic> profileChanges() {
    final trimmedName = name.value.trim();
    final trimmedDislikes = foodDislikes.value.trim();

    return {
      if (goal.value != null && goal.value!.wire != _initial.goal) 'goal': goal.value!.wire,
      if (activity.value != null && activity.value!.wire != _initial.activity)
        'activity': activity.value!.wire,
      if (diet.value != null && diet.value!.wire != _initial.foodPreference)
        'food_preference': diet.value!.wire,
      if (weightKg.value != null && weightKg.value != _initial.weightKg)
        'weight_kg': weightKg.value,
      if (trimmedName.isNotEmpty && trimmedName != (_initial.name ?? '')) 'name': trimmedName,
      if (ageYears.value != null && ageYears.value != _initial.ageYears)
        'age_years': ageYears.value,
      if (heightCm.value != null && heightCm.value != _initial.heightCm)
        'height_cm': heightCm.value,
      if (goalWeightKg.value != null && goalWeightKg.value != _initial.goalWeightKg)
        'goal_weight_kg': goalWeightKg.value,
      if (goalDeclared.value != null && goalDeclared.value!.wire != _initial.goalDeclared)
        'goal_declared': goalDeclared.value!.wire,
      // The field the MEAL_PATTERN_CONFLICT message tells the user to change.
      if (mealCount.value != null && mealCount.value!.wire != _initial.mealCount)
        'meal_count': mealCount.value!.wire,
      if (lifestyle.value != null && lifestyle.value!.wire != _initial.lifestyle)
        'lifestyle': lifestyle.value!.wire,
      // Both move together or neither does: the tier the server stores must be the one this
      // amount implies, or a coach reads a budget that contradicts the plan built from it.
      // Against the seeded value, not against null: a profile stored before the slider existed has
      // no amount, and simply opening the sheet must not look like the user changed their budget.
      if (budgetMonthlyInr.value != (_initial.budgetMonthlyInr ?? BudgetRange.defaultInr)) ...{
        'budget_monthly_inr': budgetMonthlyInr.value,
        'budget_tier': budgetTier.wire,
      },
      if (wakeTime.value != _initial.wakeTime && wakeTime.value != null)
        'wake_time': wakeTime.value,
      if (sleepTime.value != _initial.sleepTime && sleepTime.value != null)
        'sleep_time': sleepTime.value,
      if (sleepHours != null && sleepHours != _initial.sleepHours) 'sleep_hours': sleepHours,
      if (breakfastTime.value != _initial.breakfastTime && breakfastTime.value != null)
        'breakfast_time': breakfastTime.value,
      if (lunchTime.value != _initial.lunchTime && lunchTime.value != null)
        'lunch_time': lunchTime.value,
      if (eveningSnackTime.value != _initial.eveningSnackTime && eveningSnackTime.value != null)
        'evening_snack_time': eveningSnackTime.value,
      if (dinnerTime.value != _initial.dinnerTime && dinnerTime.value != null)
        'dinner_time': dinnerTime.value,
      if (trimmedDislikes != (_initial.foodDislikes ?? '')) 'food_dislikes': trimmedDislikes,
    };
  }

  Map<String, dynamic> healthChanges() {
    final nextConditions = conditions.map((c) => c.wire).toList()..sort();
    final nextAllergies = allergies.map((a) => a.wire).toList()..sort();
    final wasConditions = [..._initial.conditions]..sort();
    final wasAllergies = [..._initial.allergies]..sort();

    final nextSymptoms = digestiveSymptoms.map((d) => d.wire).toList()..sort();
    final nextInjuries = injuries.map((i) => i.wire).toList()..sort();
    final wasSymptoms = [..._initial.digestiveSymptoms]..sort();
    final wasInjuries = [..._initial.injuries]..sort();
    final trimmedMeds = medications.value.trim();

    return {
      if (nextConditions.join(',') != wasConditions.join(',')) 'conditions': nextConditions,
      if (nextAllergies.join(',') != wasAllergies.join(',')) 'allergies': nextAllergies,
      if (trimmedMeds != (_initial.medications ?? '')) 'medications': trimmedMeds,
      if (nextSymptoms.join(',') != wasSymptoms.join(',')) 'digestive_symptoms': nextSymptoms,
      if (nextInjuries.join(',') != wasInjuries.join(',')) 'injuries': nextInjuries,
      // FR-1.3: never sent for a user we never asked. The server drops them anyway, but the app
      // must not put a health field it has no reason to hold on the wire.
      if (asksFemaleHealth) ...{
        if (menstrualRegularity.value != null &&
            menstrualRegularity.value!.wire != _initial.menstrualRegularity)
          'menstrual_regularity': menstrualRegularity.value!.wire,
        if (pregnantOrBreastfeeding.value != _initial.pregnantOrBreastfeeding &&
            pregnantOrBreastfeeding.value != null)
          'pregnant_or_breastfeeding': pregnantOrBreastfeeding.value,
        if (heavyBleedingOrPain.value != _initial.heavyBleedingOrPain &&
            heavyBleedingOrPain.value != null)
          'heavy_bleeding_or_pain': heavyBleedingOrPain.value,
        if (hormonalMedication.value != _initial.hormonalMedication &&
            hormonalMedication.value != null)
          'hormonal_medication': hormonalMedication.value,
      },
    };
  }

  /// Returns true when the save succeeded. Nothing changed is also a success — there is no reason
  /// to make a user who opened the sheet and changed their mind see an error.
  Future<bool> save({required bool health}) async {
    final changes = health ? healthChanges() : profileChanges();
    if (changes.isEmpty) return true;

    saving.value = true;
    error.value = null;
    final result = health
        ? await profiles.updateHealth(changes)
        : await profiles.updateProfile(changes);
    saving.value = false;

    return result.fold((f) {
      error.value = f.userMessage;
      return false;
    }, (_) => true);
  }
}
