import {
  HttpStatus,
  Injectable,
  UnprocessableEntityException,
} from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { DataSource, Repository } from 'typeorm';
import { ProfileEntity } from './entities/profile.entity';
import { HealthProfileEntity } from './entities/health-profile.entity';
import { ConsentEntity } from './entities/consent.entity';
import { OnboardingDto } from './dto/onboarding.dto';
import { PatchHealthDto } from './dto/patch-health.dto';
import { PatchProfileDto } from './dto/patch-profile.dto';
import { bmiOf, evaluateGates, MIN_AGE, MIN_HEALTHY_BMI } from './screening';
import { GOAL_WEIGHT_TOO_LOW, UNDER_18 } from '../plans/plan-copy';
import { applyNoneExclusivity } from './onboarding-vocabulary';
import { ProfileAuditService } from './profile-audit.service';

export type HealthProfileView = {
  version: number;
  conditions: string[];
  allergies: string[];
  screened_special_diet: boolean | null;
  screened_insulin_or_kidney: boolean | null;
  screened_eating_disorder: boolean | null;
  medications: string | null;
  digestive_symptoms: string[];
  injuries: string[];
  menstrual_regularity: string | null;
  pregnant_or_breastfeeding: boolean | null;
  heavy_bleeding_or_pain: boolean | null;
  hormonal_medication: boolean | null;
  gates: string[];
  created_at: Date;
};

export type ProfileView = {
  profile: Record<string, unknown> | null;
  health_profile: HealthProfileView | null;
  latest_measurements: unknown[];
  /// Absolute URL of the user's photo, or null. Served by the files module.
  photo_url: string | null;
  /// The number this account signs in with, E.164, or null for an email or social signup.
  ///
  /// Unmasked, unlike every admin-facing view of the same column: docs/13 §4 masks a phone so one
  /// person cannot casually read another's, and this is the account holder reading their own.
  phone: string | null;
};

/// A health-profile row minus the columns that identify *that* row, ready to be saved as the next
/// version. Copying the row forward beats re-listing its columns: every time someone adds a column
/// and forgets one of these call sites, the new field silently becomes null on the user's next edit.
const IDENTITY_COLUMNS = ['id', 'version', 'createdAt'];

function withoutIdentity<T extends object>(
  row: T,
): Omit<T, 'id' | 'version' | 'createdAt'> {
  return Object.fromEntries(
    Object.entries(row).filter(([key]) => !IDENTITY_COLUMNS.includes(key)),
  ) as Omit<T, 'id' | 'version' | 'createdAt'>;
}

export type OnboardingResult = {
  user_id: number;
  health_profile_version: number;
  gates: string[];
};

@Injectable()
export class ProfileService {
  constructor(
    @InjectRepository(ProfileEntity)
    private readonly profiles: Repository<ProfileEntity>,
    @InjectRepository(HealthProfileEntity)
    private readonly healthProfiles: Repository<HealthProfileEntity>,
    @InjectRepository(ConsentEntity)
    private readonly consents: Repository<ConsentEntity>,
    private readonly dataSource: DataSource,
    private readonly audit: ProfileAuditService,
  ) {}

  /// docs/09 §4. Writes profile + a new health-profile version + consents in one transaction, so a
  /// half-onboarded user is not a state that can exist.
  async onboard(userId: number, dto: OnboardingDto): Promise<OnboardingResult> {
    this.assertConsented(dto);
    this.assertEligibleAge(dto);
    this.assertReachableGoalWeight(dto);

    const gates = evaluateGates({
      ageYears: dto.profile.age_years,
      heightCm: dto.profile.height_cm,
      weightKg: dto.profile.weight_kg,
      conditions: dto.health_profile.conditions,
      screenedSpecialDiet: dto.health_profile.screened_special_diet,
      screenedInsulinOrKidney: dto.health_profile.screened_insulin_or_kidney,
      screenedEatingDisorder: dto.health_profile.screened_eating_disorder,
    });

    // A blocked user is still stored. docs/05 §3 blocks plan *generation*, not the account — and
    // discarding the answers would force them through the same questions to reach the same refusal.
    const allGates = [...gates.blocked, ...gates.clinicianGated];

    const version = await this.dataSource.transaction(async (manager) => {
      const existing = await manager.findOne(ProfileEntity, {
        where: { userId },
      });

      await manager.save(ProfileEntity, {
        ...(existing ?? {}),
        userId,
        ageYears: dto.profile.age_years,
        heightCm: dto.profile.height_cm,
        weightKg: dto.profile.weight_kg.toFixed(2),
        goalWeightKg: dto.profile.goal_weight_kg?.toFixed(2) ?? null,
        sexAtBirth: dto.profile.sex_at_birth,
        goal: dto.profile.goal,
        activity: dto.profile.activity,
        foodPreference: dto.profile.food_preference,
        mealCount: dto.profile.meal_count,
        lifestyle: dto.profile.lifestyle,
        budgetTier: dto.profile.budget_tier,
        name: dto.profile.name?.trim() || null,
        goalDeclared: dto.profile.goal_declared ?? null,
        wakeTime: dto.profile.wake_time ?? null,
        sleepTime: dto.profile.sleep_time ?? null,
        sleepHours: dto.profile.sleep_hours?.toFixed(1) ?? null,
        breakfastTime: dto.profile.breakfast_time ?? null,
        lunchTime: dto.profile.lunch_time ?? null,
        midMorningTime: dto.profile.mid_morning_time ?? null,
        bedtimeSnackTime: dto.profile.bedtime_snack_time ?? null,
        eveningSnackTime: dto.profile.evening_snack_time ?? null,
        dinnerTime: dto.profile.dinner_time ?? null,
        foodDislikes: dto.profile.food_dislikes?.trim() || null,
        budgetMonthlyInr: dto.profile.budget_monthly_inr ?? null,
      });

      const latest = await manager.findOne(HealthProfileEntity, {
        where: { userId },
        order: { version: 'DESC' },
      });
      const nextVersion = (latest?.version ?? 0) + 1;

      await manager.save(HealthProfileEntity, {
        userId,
        version: nextVersion,
        conditions: dto.health_profile.conditions,
        allergies: dto.health_profile.allergies,
        screenedSpecialDiet: dto.health_profile.screened_special_diet ?? null,
        screenedInsulinOrKidney:
          dto.health_profile.screened_insulin_or_kidney ?? null,
        screenedEatingDisorder:
          dto.health_profile.screened_eating_disorder ?? null,
        ...this.extraHealthFields(dto.health_profile, dto.profile.sex_at_birth),
        gates: allGates,
      });

      await manager.save(
        ConsentEntity,
        dto.consents.map((c) => ({ userId, type: c.type, granted: c.granted })),
      );

      return nextVersion;
    });

    return {
      user_id: userId,
      health_profile_version: version,
      gates: allGates,
    };
  }

  /// docs/09 §4. `latest_measurements` is always empty until `POST /measurements` exists — the key
  /// is present so the client contract does not change when it lands.
  async getProfile(
    userId: number,
    /// Both come from the `user` row, which the controller has already loaded — passing them beats
    /// a second read of the same row from here.
    account: { photoUrl?: string | null; phone?: string | null } = {},
  ): Promise<ProfileView> {
    const [profile, health] = await Promise.all([
      this.profiles.findOne({ where: { userId } }),
      this.latestHealthProfile(userId),
    ]);

    return {
      profile: profile ? this.toProfileView(profile) : null,
      health_profile: health ? this.toHealthView(health) : null,
      latest_measurements: [],
      photo_url: account.photoUrl ?? null,
      phone: account.phone ?? null,
    };
  }

  /// docs/09 §4: a PATCH creates a NEW version rather than mutating the current one. A plan is
  /// traceable to the health profile it was generated from, and rewriting history breaks that.
  async patchHealth(
    userId: number,
    dto: PatchHealthDto,
  ): Promise<HealthProfileView> {
    const current = await this.latestHealthProfile(userId);

    if (!current) {
      throw new UnprocessableEntityException({
        status: HttpStatus.UNPROCESSABLE_ENTITY,
        error: {
          code: 'ONBOARDING_REQUIRED',
          user_message: 'Please finish setting up your profile first.',
        },
      });
    }

    const profile = await this.profiles.findOne({ where: { userId } });
    const merged = {
      ...withoutIdentity(current),
      conditions: dto.conditions ?? current.conditions,
      allergies: dto.allergies ?? current.allergies,
      screenedSpecialDiet:
        dto.screened_special_diet ?? current.screenedSpecialDiet,
      screenedInsulinOrKidney:
        dto.screened_insulin_or_kidney ?? current.screenedInsulinOrKidney,
      screenedEatingDisorder:
        dto.screened_eating_disorder ?? current.screenedEatingDisorder,
      medications: dto.medications?.trim() ?? current.medications,
      digestiveSymptoms: dto.digestive_symptoms
        ? applyNoneExclusivity(dto.digestive_symptoms, 'none')
        : current.digestiveSymptoms,
      injuries: dto.injuries
        ? applyNoneExclusivity(dto.injuries, 'none')
        : current.injuries,
      menstrualRegularity:
        dto.menstrual_regularity ?? current.menstrualRegularity,
      pregnantOrBreastfeeding:
        dto.pregnant_or_breastfeeding ?? current.pregnantOrBreastfeeding,
      heavyBleedingOrPain:
        dto.heavy_bleeding_or_pain ?? current.heavyBleedingOrPain,
      hormonalMedication: dto.hormonal_medication ?? current.hormonalMedication,
    };

    // The gates are re-evaluated on every edit — a condition added later must gate exactly as it
    // would have at onboarding.
    const gates = evaluateGates({
      ageYears: profile?.ageYears ?? 0,
      heightCm: profile?.heightCm ?? 0,
      weightKg: Number(profile?.weightKg ?? 0),
      conditions: merged.conditions,
      screenedSpecialDiet: merged.screenedSpecialDiet,
      screenedInsulinOrKidney: merged.screenedInsulinOrKidney,
      screenedEatingDisorder: merged.screenedEatingDisorder,
    });

    const saved = await this.dataSource.transaction(async (manager) => {
      const row = (await manager.save(HealthProfileEntity, {
        ...merged,
        userId,
        version: current.version + 1,
        gates: [...gates.blocked, ...gates.clinicianGated],
      })) as HealthProfileEntity;

      // The health profile is already versioned, so the previous values are recoverable — but only
      // by diffing two versions. This makes "when did they add that allergy" a single query.
      await this.audit.record(manager, {
        userId,
        entity: 'health_profile',
        changes: ProfileAuditService.diff(
          this.toHealthView(current) as unknown as Record<string, unknown>,
          this.toHealthView(row) as unknown as Record<string, unknown>,
        ).filter((c) => c.field !== 'version' && c.field !== 'created_at'),
        changedByUserId: userId,
        source: 'PATCH /profile/health',
      });

      return row;
    });

    return this.toHealthView(saved);
  }

  /// docs/09 §4. Edits the profile half. Omitted fields carry forward.
  ///
  /// Anthropometrics feed the docs/05 §3 BMI and age gates, so a change here re-runs them and
  /// records the result as a new health-profile version. Without that, editing weight down to a
  /// BMI of 15 would leave a stale "no gates" row and the user would keep getting plans.
  async patchProfile(
    userId: number,
    dto: PatchProfileDto,
  ): Promise<{
    profile: Record<string, unknown>;
    health_profile: HealthProfileView | null;
  }> {
    const current = await this.profiles.findOne({ where: { userId } });

    if (!current) {
      throw new UnprocessableEntityException({
        status: HttpStatus.UNPROCESSABLE_ENTITY,
        error: {
          code: 'ONBOARDING_REQUIRED',
          user_message: 'Please finish setting up your profile first.',
        },
      });
    }

    const merged: ProfileEntity = {
      ...current,
      ageYears: dto.age_years ?? current.ageYears,
      heightCm: dto.height_cm ?? current.heightCm,
      weightKg: dto.weight_kg?.toFixed(2) ?? current.weightKg,
      goalWeightKg: dto.goal_weight_kg?.toFixed(2) ?? current.goalWeightKg,
      sexAtBirth: dto.sex_at_birth ?? current.sexAtBirth,
      goal: dto.goal ?? current.goal,
      activity: dto.activity ?? current.activity,
      foodPreference: dto.food_preference ?? current.foodPreference,
      mealCount: dto.meal_count ?? current.mealCount,
      lifestyle: dto.lifestyle ?? current.lifestyle,
      budgetTier: dto.budget_tier ?? current.budgetTier,
      name: dto.name?.trim() ?? current.name,
      goalDeclared: dto.goal_declared ?? current.goalDeclared,
      wakeTime: dto.wake_time ?? current.wakeTime,
      sleepTime: dto.sleep_time ?? current.sleepTime,
      sleepHours: dto.sleep_hours?.toFixed(1) ?? current.sleepHours,
      breakfastTime: dto.breakfast_time ?? current.breakfastTime,
      lunchTime: dto.lunch_time ?? current.lunchTime,
      midMorningTime: dto.mid_morning_time ?? current.midMorningTime,
      bedtimeSnackTime: dto.bedtime_snack_time ?? current.bedtimeSnackTime,
      eveningSnackTime: dto.evening_snack_time ?? current.eveningSnackTime,
      dinnerTime: dto.dinner_time ?? current.dinnerTime,
      foodDislikes: dto.food_dislikes?.trim() ?? current.foodDislikes,
      budgetMonthlyInr: dto.budget_monthly_inr ?? current.budgetMonthlyInr,
    };

    // Recorded in the same transaction as the write, so an audit row cannot survive a rollback.
    await this.dataSource.transaction(async (manager) => {
      await manager.save(ProfileEntity, merged);
      await this.audit.record(manager, {
        userId,
        entity: 'profile',
        changes: ProfileAuditService.diff(
          this.toProfileView(current),
          this.toProfileView(merged),
        ),
        changedByUserId: userId,
        source: 'PATCH /profile',
      });
    });

    const health = await this.latestHealthProfile(userId);
    const anthropometricsChanged =
      dto.age_years !== undefined ||
      dto.height_cm !== undefined ||
      dto.weight_kg !== undefined;

    // Only version the health profile when something the gates actually depend on moved. Changing
    // a budget tier should not spawn a health-profile version.
    let view = health ? this.toHealthView(health) : null;
    if (health && anthropometricsChanged) {
      const gates = evaluateGates({
        ageYears: merged.ageYears,
        heightCm: merged.heightCm,
        weightKg: Number(merged.weightKg),
        conditions: health.conditions,
        screenedSpecialDiet: health.screenedSpecialDiet,
        screenedInsulinOrKidney: health.screenedInsulinOrKidney,
        screenedEatingDisorder: health.screenedEatingDisorder,
      });

      // This version exists only to record a new gate result — nothing else about it changed.
      const saved = await this.healthProfiles.save({
        ...withoutIdentity(health),
        version: health.version + 1,
        gates: [...gates.blocked, ...gates.clinicianGated],
      });
      view = this.toHealthView(saved as HealthProfileEntity);
    }

    return { profile: this.toProfileView(merged), health_profile: view };
  }

  private latestHealthProfile(
    userId: number,
  ): Promise<HealthProfileEntity | null> {
    return this.healthProfiles.findOne({
      where: { userId },
      order: { version: 'DESC' },
    });
  }

  private toProfileView(p: ProfileEntity): Record<string, unknown> {
    return {
      age_years: p.ageYears,
      height_cm: p.heightCm,
      weight_kg: Number(p.weightKg),
      goal_weight_kg: p.goalWeightKg === null ? null : Number(p.goalWeightKg),
      sex_at_birth: p.sexAtBirth,
      goal: p.goal,
      activity: p.activity,
      food_preference: p.foodPreference,
      meal_count: p.mealCount,
      lifestyle: p.lifestyle,
      budget_tier: p.budgetTier,
      name: p.name,
      goal_declared: p.goalDeclared,
      wake_time: p.wakeTime,
      sleep_time: p.sleepTime,
      sleep_hours: p.sleepHours === null ? null : Number(p.sleepHours),
      breakfast_time: p.breakfastTime,
      lunch_time: p.lunchTime,
      mid_morning_time: p.midMorningTime,
      bedtime_snack_time: p.bedtimeSnackTime,
      evening_snack_time: p.eveningSnackTime,
      dinner_time: p.dinnerTime,
      food_dislikes: p.foodDislikes,
      budget_monthly_inr: p.budgetMonthlyInr,
    };
  }

  private toHealthView(h: HealthProfileEntity): HealthProfileView {
    return {
      version: h.version,
      conditions: h.conditions,
      allergies: h.allergies,
      screened_special_diet: h.screenedSpecialDiet,
      screened_insulin_or_kidney: h.screenedInsulinOrKidney,
      screened_eating_disorder: h.screenedEatingDisorder,
      medications: h.medications,
      digestive_symptoms: h.digestiveSymptoms ?? [],
      injuries: h.injuries ?? [],
      menstrual_regularity: h.menstrualRegularity,
      pregnant_or_breastfeeding: h.pregnantOrBreastfeeding,
      heavy_bleeding_or_pain: h.heavyBleedingOrPain,
      hormonal_medication: h.hormonalMedication,
      gates: h.gates,
      created_at: h.createdAt,
    };
  }

  /// The fields added after the first contract, normalised.
  ///
  /// FR-1.3 / docs/13: the menstrual-health answers are stored ONLY for a female user. The app does
  /// not ask otherwise, but a hand-rolled request could still send them, and a health field with no
  /// clinical purpose for that user is one we must not keep.
  private extraHealthFields(
    input: {
      medications?: string;
      digestive_symptoms?: string[];
      injuries?: string[];
      menstrual_regularity?: string;
      pregnant_or_breastfeeding?: boolean;
      heavy_bleeding_or_pain?: boolean;
      hormonal_medication?: boolean;
    },
    sexAtBirth: string,
  ) {
    const isFemale = sexAtBirth === 'female';
    return {
      medications: input.medications?.trim() || null,
      digestiveSymptoms: applyNoneExclusivity(
        input.digestive_symptoms ?? [],
        'none',
      ),
      injuries: applyNoneExclusivity(input.injuries ?? [], 'none'),
      menstrualRegularity: isFemale
        ? (input.menstrual_regularity ?? null)
        : null,
      pregnantOrBreastfeeding: isFemale
        ? (input.pregnant_or_breastfeeding ?? null)
        : null,
      heavyBleedingOrPain: isFemale
        ? (input.heavy_bleeding_or_pain ?? null)
        : null,
      hormonalMedication: isFemale ? (input.hormonal_medication ?? null) : null,
    };
  }

  async hasCompletedOnboarding(userId: number): Promise<boolean> {
    return (await this.profiles.countBy({ userId })) > 0;
  }

  /// FR-1.2: an applicant under 18 is REFUSED, not stored and gated.
  ///
  /// Every other gate keeps the answers, because docs/05 §3 blocks plan generation rather than the
  /// account and re-asking the same questions to reach the same refusal helps nobody. This one is
  /// different in kind: FR-1.2 says "no profile row is created, no health field is persisted", and
  /// for a minor that is a DPDP obligation rather than a preference — a gate flag on a stored row
  /// does not un-store their height, weight and conditions.
  private assertEligibleAge(dto: OnboardingDto): void {
    if (dto.profile.age_years >= MIN_AGE) return;

    throw new UnprocessableEntityException({
      status: HttpStatus.UNPROCESSABLE_ENTITY,
      error: {
        code: 'AGE_INELIGIBLE',
        // docs/05 §7, verbatim. Rule 7 makes this the only string the app may show.
        user_message: UNDER_18,
      },
    });
  }

  /// FR-1.5 / docs/05 §2: "Goal weight implies BMI < 18.5 → reject at input with plain
  /// explanation. No override." At input, so nothing is written — a target nobody may pursue is
  /// not a profile worth keeping, and storing it would leave the engine to refuse it later.
  private assertReachableGoalWeight(dto: OnboardingDto): void {
    const goal = dto.profile.goal_weight_kg;
    if (goal == null) return;
    if (bmiOf(goal, dto.profile.height_cm) >= MIN_HEALTHY_BMI) return;

    throw new UnprocessableEntityException({
      status: HttpStatus.UNPROCESSABLE_ENTITY,
      error: {
        code: 'VALIDATION_FAILED',
        user_message: GOAL_WEIGHT_TOO_LOW,
      },
    });
  }

  /// FR-1.7: no health field is stored until storage itself is consented to.
  private assertConsented(dto: OnboardingDto): void {
    const storage = dto.consents.find((c) => c.type === 'health_data_storage');

    if (!storage?.granted) {
      throw new UnprocessableEntityException({
        status: HttpStatus.UNPROCESSABLE_ENTITY,
        error: {
          code: 'CONSENT_REQUIRED',
          user_message:
            'We need your permission to store your health details before we can continue.',
        },
      });
    }
  }
}
