import {
  HttpStatus,
  Injectable,
  UnprocessableEntityException,
} from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import {
  MealPatternError,
  type Constraints,
  type EngineInput,
} from '@eatzify/diet-engine';
import { EngineService } from '../modules/engine';
import { PlanEntity } from './entities/plan.entity';
import { ProfileEntity } from '../profile/entities/profile.entity';
import { HealthProfileEntity } from '../profile/entities/health-profile.entity';
import {
  gateMessage,
  mealPatternConflictMessage,
  warningsForUser,
  type UserFacingWarning,
} from './plan-copy';
import { BillingService } from '../billing/billing.service';
import { diaryDateFor } from './diary-date';
import {
  PlanOptionsService,
  type FoodOptionView,
} from './plan-options.service';

export type MealTargetView = {
  slot: string;
  /// Share of the day's energy, 0–1. Kept alongside the kcal so a client can show either.
  pct: number;
  kcal: number;
  protein_g: number;
  carb_g: number;
  fat_g: number;
};

export type PlanResponse = {
  plan: {
    id: string;
    valid_from: string;
    targets: Record<string, number> | null;
    /// Per-slot split from the rule pack (docs/04 §5). CLAUDE.md rule 2: the split is applied here,
    /// never in the app — a client multiplying percentages is a client computing a target.
    meal_targets: MealTargetView[];
    meals: unknown[];
  };
  rule_pack_version: string;
  warnings: UserFacingWarning[];
  trace_available: boolean;
};

@Injectable()
export class PlansService {
  constructor(
    @InjectRepository(PlanEntity)
    private readonly plans: Repository<PlanEntity>,
    @InjectRepository(ProfileEntity)
    private readonly profiles: Repository<ProfileEntity>,
    @InjectRepository(HealthProfileEntity)
    private readonly healthProfiles: Repository<HealthProfileEntity>,
    private readonly engine: EngineService,
    private readonly billing: BillingService,
    private readonly planOptions: PlanOptionsService,
  ) {}

  /// docs/09 §4.2. Inputs come from the server-side profile — never from the client, which is why
  /// the request body carries only a reason.
  async generate(
    userId: number,
    planDate: string,
    regenerateReason: string | null,
    idempotencyKey: string | null,
  ): Promise<PlanResponse> {
    if (idempotencyKey) {
      const existing = await this.plans.findOne({ where: { idempotencyKey } });
      // A retried request returns its original plan rather than billing a second generation.
      if (existing) return this.toResponse(existing);
    }

    // docs/09 §10: plan generation is entitlement-driven (FREE 1/day, BASIC 2, PRO 3). Checked
    // before the engine runs — a blocked user should not cost a computation.
    await this.enforceDailyLimit(userId, planDate);

    const [profile, health] = await Promise.all([
      this.profiles.findOne({ where: { userId } }),
      this.healthProfiles.findOne({
        where: { userId },
        order: { version: 'DESC' },
      }),
    ]);

    if (!profile || !health) {
      throw new UnprocessableEntityException({
        status: HttpStatus.UNPROCESSABLE_ENTITY,
        error: {
          code: 'ONBOARDING_REQUIRED',
          user_message: 'Please finish setting up your profile first.',
        },
      });
    }

    const input = this.engineInput(userId, profile, health, planDate);

    // The engine rejects an input the user can fix — a meal pattern too small for a condition's
    // minimum eating occasions (docs/04 §6 priority 5). That is a 422 they can act on, not the 500
    // an uncaught throw produced.
    let output: ReturnType<typeof this.engine.generate>;
    try {
      output = this.engine.generate(input);
    } catch (error) {
      if (error instanceof MealPatternError) {
        throw new UnprocessableEntityException({
          status: HttpStatus.UNPROCESSABLE_ENTITY,
          error: {
            code: 'MEAL_PATTERN_CONFLICT',
            user_message: mealPatternConflictMessage(error.required),
            details: {
              meal_count: error.mealCount,
              available: error.available,
              required: error.required,
            },
          },
        });
      }
      throw error;
    }
    const blocking = output.gates.filter((g) => g.blocking);

    // docs/04 §2 step 6: a blocking gate means no plan is emitted at all. Nothing is persisted —
    // a stored row with null targets would look like a plan to every later query.
    if (blocking.length > 0) {
      throw new UnprocessableEntityException({
        status: HttpStatus.UNPROCESSABLE_ENTITY,
        error: {
          code: 'PLAN_GATE_BLOCKED',
          user_message: gateMessage(blocking[0].code),
          details: { gate: blocking[0].code },
        },
      });
    }

    const saved = await this.plans.save({
      userId,
      planDate,
      rulePackVersion: output.packVersion,
      healthProfileVersion: health.version,
      targets: output.targets as unknown as Record<string, number> | null,
      derived: output.derived as unknown as Record<string, unknown> | null,
      mealTargets: [...output.mealTargets],
      constraints: output.constraints as unknown as Record<
        string,
        unknown
      > | null,
      warnings: [...output.warnings],
      gates: output.gates.map((g) => g.code),
      trace: [...output.trace],
      regenerateReason,
      idempotencyKey,
    });

    return this.toResponse(saved as PlanEntity);
  }

  /// docs/09 §10. Counts today's plans against the tier's allowance and refuses with 429-style
  /// copy once spent. The count is of plans actually persisted, so a gate-blocked attempt — which
  /// stores nothing — never costs someone their daily allowance.

  /// The engine's input for a user. One definition, so `generate` and `options` cannot describe the
  /// same person differently — the constraints the options are filtered by have to be the
  /// constraints the plan was built from, or the list contradicts the plan beside it.
  private engineInput(
    userId: number,
    profile: ProfileEntity,
    health: HealthProfileEntity | null,
    planDate: string,
  ): EngineInput {
    return {
      userId: String(userId),
      planDate,
      ageYears: profile.ageYears,
      sexAtBirth: profile.sexAtBirth as EngineInput['sexAtBirth'],
      heightCm: profile.heightCm,
      weightKg: Number(profile.weightKg),
      goal: profile.goal as EngineInput['goal'],
      activityLevel: profile.activity as EngineInput['activityLevel'],
      conditions: (health?.conditions ?? []) as EngineInput['conditions'],
      foodPreference: profile.foodPreference as EngineInput['foodPreference'],
      foodAllergies: health?.allergies ?? [],
      budgetTier: profile.budgetTier as EngineInput['budgetTier'],
      lifestyle: profile.lifestyle as EngineInput['lifestyle'],
      mealCount: profile.mealCount as EngineInput['mealCount'],
    };
  }

  /// Foods the user may pick from, for the plan they currently have (D-82).
  ///
  /// The engine is re-run purely to obtain the `constraints` its rule pack derives for this user's
  /// conditions — `excludeTags` and `preferTags`. Reading those from the pack by hand here would be
  /// a second implementation of the one thing docs/04 says the pack owns.
  async options(userId: number): Promise<Record<string, FoodOptionView[]>> {
    const [profile, health] = await Promise.all([
      this.profiles.findOne({ where: { userId } }),
      this.healthProfiles.findOne({
        where: { userId },
        order: { version: 'DESC' },
      }),
    ]);
    if (!profile) return {};

    let constraints: Constraints | null = null;
    try {
      constraints = this.engine.generate(
        this.engineInput(userId, profile, health, diaryDateFor(new Date())),
      ).constraints;
    } catch {
      // A user whose meal pattern conflicts with a condition still gets to browse food. The plan is
      // what that conflict blocks, not the list.
      constraints = null;
    }

    // The slots this user's plan actually has, so the response carries no key the screen will not
    // render — a five-meal pattern must not be offered a bedtime list it never shows.
    const plan = await this.plans.findOne({
      where: { userId },
      order: { createdAt: 'DESC' },
    });
    const slots = (plan?.mealTargets ?? [])
      .map((m) => (m as { slot?: string }).slot)
      .filter((slot): slot is string => typeof slot === 'string');

    return this.planOptions.forUser(profile, health, constraints, slots);
  }

  private async enforceDailyLimit(
    userId: number,
    planDate: string,
  ): Promise<void> {
    const { entitlements } = await this.billing.entitlements(userId);
    const allowance = entitlements['plan.regenerate_per_day'];

    const used = await this.plans.count({ where: { userId, planDate } });
    if (used < allowance) return;

    throw new UnprocessableEntityException({
      status: HttpStatus.UNPROCESSABLE_ENTITY,
      error: {
        code: 'ENTITLEMENT_REQUIRED',
        user_message:
          `You've made ${allowance} plan${allowance === 1 ? '' : 's'} today. ` +
          'You can make another tomorrow, or upgrade for more.',
        details: { entitlement: 'plan.regenerate_per_day' },
      },
    });
  }

  /// The most recent plan for a date, or null. Used by the Plan tab.
  async latest(userId: number): Promise<PlanResponse | null> {
    const plan = await this.plans.findOne({
      where: { userId },
      order: { createdAt: 'DESC' },
    });

    return plan ? this.toResponse(plan) : null;
  }

  /// Splits the day's targets across the rule pack's meal slots. Rounded once, here, so the app
  /// never has to decide how to round somebody's protein.
  private toMealTargets(plan: PlanEntity): MealTargetView[] {
    const targets = plan.targets;
    if (!targets) return [];

    return (plan.mealTargets as { slot: string; pct: number }[]).map((m) => ({
      slot: m.slot,
      pct: m.pct,
      kcal: Math.round(targets.kcal * m.pct),
      protein_g: Math.round(targets.proteinG * m.pct),
      carb_g: Math.round(targets.carbG * m.pct),
      fat_g: Math.round(targets.fatG * m.pct),
    }));
  }

  private toResponse(plan: PlanEntity): PlanResponse {
    return {
      plan: {
        id: plan.id,
        valid_from: plan.planDate,
        targets: plan.targets,
        meal_targets: this.toMealTargets(plan),
        // Empty until the food database lands (E2) — engine steps 11/13/14 need it to fill meals.
        meals: [],
      },
      rule_pack_version: plan.rulePackVersion,
      warnings: warningsForUser(plan.warnings),
      trace_available: plan.trace.length > 0,
    };
  }
}
