// GetX exports its own `Condition`; ours is the docs/03 §2 health condition.
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart' hide Condition;
import 'package:health_pro/domain/entities/onboarding_enums.dart';
import 'package:health_pro/presentation/features/onboarding/onboarding_controller.dart';

/// Fills everything the submission requires, so each test only sets what it is about.
OnboardingController filled({SexAtBirth sex = SexAtBirth.female}) => OnboardingController()
  ..name.value = 'Asha'
  ..ageYears.value = 29
  ..heightCm.value = 165
  ..weightKg.value = 72
  ..sexAtBirth.value = sex
  ..goalDeclared.value = GoalDeclared.weightLoss
  ..activity.value = ActivityLevel.moderate
  ..foodPreference.value = FoodPreference.veg
  ..mealCount.value = MealCount.four
  ..lifestyle.value = Lifestyle.office
  ..budgetMonthlyInr.value = 8000
  ..conditions.assignAll({Condition.none})
  ..consentGranted.value = true;

void main() {
  group("the seven-goal list maps onto the engine's three", () {
    test('every declared goal resolves to a Goal the rule pack understands', () {
      for (final declared in GoalDeclared.values) {
        expect(Goal.values, contains(declared.engineGoal), reason: declared.wire);
      }
    });

    test('both the declared goal and the engine goal are sent', () {
      final c = filled()..goalDeclared.value = GoalDeclared.generalFitness;
      final profile = c.buildSubmission()!.toJson()['profile']! as Map<String, dynamic>;

      expect(profile['goal_declared'], 'general_fitness');
      expect(profile['goal'], 'maintenance', reason: 'the engine only knows three directions');
    });

    test('weight gain is a surplus, not maintenance', () {
      expect(GoalDeclared.weightGain.engineGoal, Goal.muscleGain);
    });
  });

  group('daily routine, meal timings and free text reach the wire', () {
    test('every new profile field is in the body', () {
      final c = filled()
        ..goalWeightKg.value = 65
        ..wakeTime.value = '06:30'
        ..sleepTime.value = '23:00'
        ..breakfastTime.value = '08:00'
        ..lunchTime.value = '13:30'
        ..eveningSnackTime.value = '17:30'
        ..dinnerTime.value = '20:30'
        ..foodDislikes.value = 'karela';

      final profile = c.buildSubmission()!.toJson()['profile']! as Map<String, dynamic>;

      expect(profile['name'], 'Asha');
      expect(profile['goal_weight_kg'], 65);
      expect(profile['wake_time'], '06:30');
      expect(profile['sleep_time'], '23:00');
      // Derived from 23:00 to 06:30 rather than typed (D-77).
      expect(profile['sleep_hours'], 7.5);
      expect(profile['breakfast_time'], '08:00');
      expect(profile['lunch_time'], '13:30');
      expect(profile['evening_snack_time'], '17:30');
      expect(profile['dinner_time'], '20:30');
      expect(profile['food_dislikes'], 'karela');
    });

    test('an unanswered optional field is omitted, not sent as an empty string', () {
      final profile = filled().buildSubmission()!.toJson()['profile']! as Map<String, dynamic>;

      expect(profile.containsKey('food_dislikes'), isFalse, reason: 'blank is not an answer');
    });

    /// D-170: wake, bedtime and the meal hours open PREFILLED, so they are always answered. The
    /// step is a confirmation rather than five questions, and a default the user can see and
    /// correct beats an empty field they must fill to get past.
    test('the clock fields are always sent, because they start with a sensible default', () {
      final profile = filled().buildSubmission()!.toJson()['profile']! as Map<String, dynamic>;

      for (final key in [
        'wake_time',
        'sleep_time',
        'breakfast_time',
        'lunch_time',
        'dinner_time',
      ]) {
        expect(profile.containsKey(key), isTrue, reason: key);
      }
    });
  });

  group('health declarations', () {
    test('medicines, symptoms and injuries are sent', () {
      final c = filled()
        ..medications.value = 'Metformin 500mg'
        ..toggleDigestiveSymptom(DigestiveSymptom.acidity)
        ..toggleInjury(InjuryArea.kneePain);

      final health = c.buildSubmission()!.toJson()['health_profile']! as Map<String, dynamic>;

      expect(health['medications'], 'Metformin 500mg');
      expect(health['digestive_symptoms'], ['acidity']);
      expect(health['injuries'], ['knee_pain']);
    });

    test('"none" clears the rest, and picking a symptom clears "none"', () {
      final c = filled()
        ..toggleDigestiveSymptom(DigestiveSymptom.gas)
        ..toggleDigestiveSymptom(DigestiveSymptom.bloating);
      expect(c.digestiveSymptoms, hasLength(2));

      c.toggleDigestiveSymptom(DigestiveSymptom.none);
      expect(c.digestiveSymptoms, {DigestiveSymptom.none}, reason: 'none is exclusive');

      c.toggleDigestiveSymptom(DigestiveSymptom.ibs);
      expect(c.digestiveSymptoms, {DigestiveSymptom.ibs}, reason: 'and it steps aside');
    });

    test('the four new conditions are offered and none of them gates a plan', () {
      const added = {
        Condition.highCholesterol,
        Condition.fattyLiver,
        Condition.heartProblem,
        Condition.digestiveIssue,
      };
      for (final condition in added) {
        expect(Condition.values, contains(condition));
        expect(
          condition.isBlockingGate,
          isFalse,
          reason: 'gate classification is a docs/05 decision, not one the app makes',
        );
      }
    });
  });

  group('FR-1.3 — menstrual health is asked of women only', () {
    test('a female user is asked, and the answers are sent', () {
      final c = filled()
        ..menstrualRegularity.value = MenstrualRegularity.irregular
        ..pregnantOrBreastfeeding.value = false
        ..heavyBleedingOrPain.value = true
        ..hormonalMedication.value = false;

      expect(c.asksFemaleHealth, isTrue);
      final health = c.buildSubmission()!.toJson()['health_profile']! as Map<String, dynamic>;

      expect(health['menstrual_regularity'], 'irregular');
      expect(health['pregnant_or_breastfeeding'], false);
      expect(health['heavy_bleeding_or_pain'], true);
      expect(health['hormonal_medication'], false);
    });

    test('a male user never puts them on the wire, even if the fields hold values', () {
      final c = filled(sex: SexAtBirth.male)
        // Could only happen if the user answered as female and then went back and changed it.
        ..menstrualRegularity.value = MenstrualRegularity.regular
        ..pregnantOrBreastfeeding.value = true;

      expect(c.asksFemaleHealth, isFalse);
      final health = c.buildSubmission()!.toJson()['health_profile']! as Map<String, dynamic>;

      expect(health.containsKey('menstrual_regularity'), isFalse);
      expect(health.containsKey('pregnant_or_breastfeeding'), isFalse);
    });

    test('the step is dropped from the flow entirely, not skipped mid-count', () {
      final male = filled(sex: SexAtBirth.male);
      final female = filled();

      expect(female.totalSteps, male.totalSteps + 1);
    });
  });
}
