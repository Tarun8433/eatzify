import 'package:flutter_test/flutter_test.dart';
import 'package:health_pro/domain/entities/onboarding_enums.dart';
import 'package:health_pro/domain/usecases/validate_onboarding.dart';

void main() {
  group('FR-1.2 — age gate', () {
    test('refuses under 18', () {
      expect(ValidateOnboarding.age(17).reject, OnboardingReject.ageBelowMinimum);
      // docs/16 GV-07: "age 17y11m -> AGE_INELIGIBLE at the API boundary, no engine call at all"
      expect(ValidateOnboarding.age(0).reject, OnboardingReject.ageBelowMinimum);
    });

    test('accepts exactly 18 and 99', () {
      expect(ValidateOnboarding.age(18).reject, isNull);
      expect(ValidateOnboarding.age(99).reject, isNull);
    });

    test('refuses above 99 as out of range, not as an age gate', () {
      expect(ValidateOnboarding.age(100).reject, OnboardingReject.ageOutOfRange);
    });
  });

  group('FR-1.4 — plausible ranges with a confirm step', () {
    test('refuses heights outside 120-220 cm', () {
      expect(ValidateOnboarding.heightCm(119).reject, OnboardingReject.heightOutOfRange);
      expect(ValidateOnboarding.heightCm(221).reject, OnboardingReject.heightOutOfRange);
    });

    test('accepts an ordinary height without a confirm', () {
      final r = ValidateOnboarding.heightCm(165);
      expect(r.reject, isNull);
      expect(r.confirmNeeded, isFalse);
    });

    test('accepts an unusual but legal height only after confirmation', () {
      final r = ValidateOnboarding.heightCm(210);
      expect(r.reject, isNull);
      expect(r.confirmNeeded, isTrue);
    });

    test('refuses weights outside 30-250 kg', () {
      expect(ValidateOnboarding.weightKg(29.9).reject, OnboardingReject.weightOutOfRange);
      expect(ValidateOnboarding.weightKg(250.1).reject, OnboardingReject.weightOutOfRange);
    });

    test('asks to confirm an unusual weight', () {
      expect(ValidateOnboarding.weightKg(180).confirmNeeded, isTrue);
      expect(ValidateOnboarding.weightKg(72).confirmNeeded, isFalse);
    });
  });

  group('FR-1.5 / docs/05 §5 — goal weight below BMI 18.5 is refused, no override', () {
    test('refuses a goal weight implying BMI under 18.5', () {
      // 165 cm: BMI 18.5 is 50.4 kg
      expect(
        ValidateOnboarding.goalWeightKg(45, heightCm: 165).reject,
        OnboardingReject.goalWeightBelowHealthyBmi,
      );
    });

    test('accepts a goal weight at or above BMI 18.5', () {
      expect(ValidateOnboarding.goalWeightKg(55, heightCm: 165).reject, isNull);
      expect(ValidateOnboarding.goalWeightKg(50.4, heightCm: 165).reject, isNull);
    });
  });

  group('docs/03 §2 — "none" is exclusive', () {
    test('rejects none alongside a real condition', () {
      final r = ValidateOnboarding.conditions({Condition.none, Condition.pcos});
      expect(r.reject, OnboardingReject.conditionNoneNotExclusive);
    });

    test('accepts none alone, and real conditions together', () {
      expect(ValidateOnboarding.conditions({Condition.none}).reject, isNull);
      expect(
        ValidateOnboarding.conditions({Condition.pcos, Condition.hypertension}).reject,
        isNull,
      );
    });

    test('tapping none clears every other selection', () {
      final result = ValidateOnboarding.toggleCondition({
        Condition.pcos,
        Condition.hypertension,
      }, Condition.none);
      expect(result, {Condition.none});
    });

    test('tapping a condition clears none', () {
      final result = ValidateOnboarding.toggleCondition({Condition.none}, Condition.pcos);
      expect(result, {Condition.pcos});
    });

    test('tapping a selected condition deselects it', () {
      final result = ValidateOnboarding.toggleCondition({
        Condition.pcos,
        Condition.hypertension,
      }, Condition.pcos);
      expect(result, {Condition.hypertension});
    });

    test('tapping none while none is selected clears everything', () {
      expect(ValidateOnboarding.toggleCondition({Condition.none}, Condition.none), isEmpty);
    });
  });

  group('FR-1.3 — the pregnancy question is asked of exactly one group', () {
    test('asked of women aged 18-50', () {
      for (final age in [18, 30, 50]) {
        expect(
          ValidateOnboarding.shouldAskPregnancyStatus(sex: SexAtBirth.female, ageYears: age),
          isTrue,
          reason: 'age $age',
        );
      }
    });

    test('not asked of women outside that band', () {
      expect(
        ValidateOnboarding.shouldAskPregnancyStatus(sex: SexAtBirth.female, ageYears: 51),
        isFalse,
      );
    });

    test('not asked of men or undisclosed — collecting it would have no clinical purpose', () {
      for (final sex in [SexAtBirth.male, SexAtBirth.intersexPreferNotSay]) {
        expect(
          ValidateOnboarding.shouldAskPregnancyStatus(sex: sex, ageYears: 30),
          isFalse,
          reason: sex.wire,
        );
      }
    });
  });

  group('docs/05 §3 — blocking gates', () {
    test('every BLOCK-list condition is detected', () {
      const blocking = {
        Condition.ckd,
        Condition.pregnancy,
        Condition.lactation,
        Condition.hyperthyroid,
        Condition.postSurgery,
      };
      for (final c in blocking) {
        expect(ValidateOnboarding.blockingGates({c}), {c}, reason: c.wire);
      }
    });

    test('plan-with-constraints conditions are not gates', () {
      const constrained = {
        Condition.type2Diabetes,
        Condition.prediabetes,
        Condition.hypertension,
        Condition.pcos,
        Condition.hypothyroid,
      };
      expect(ValidateOnboarding.blockingGates(constrained), isEmpty);
    });
  });

  group('FR-1.7 — consent precedes storing any health field', () {
    test('refuses without consent', () {
      expect(ValidateOnboarding.consent(granted: false).reject, OnboardingReject.consentNotGiven);
    });

    test('accepts with consent', () {
      expect(ValidateOnboarding.consent(granted: true).reject, isNull);
    });
  });

  group('CLAUDE.md rule 4 — wire values never reach a user', () {
    test('every enum carries a snake_case wire name matching docs/03 §2', () {
      expect(Goal.fatLoss.wire, 'fat_loss');
      expect(SexAtBirth.intersexPreferNotSay.wire, 'intersex_prefer_not_say');
      expect(MealCount.fiveOrSix.wire, '5_6');
      expect(FoodAllergy.wheatGluten.wire, 'wheat_gluten');
      for (final c in Condition.values) {
        expect(c.wire, matches(RegExp(r'^[a-z0-9_]+$')), reason: c.name);
      }
    });
  });
}
