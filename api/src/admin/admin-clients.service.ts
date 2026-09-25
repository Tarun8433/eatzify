import { Injectable, NotFoundException } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { ProfileEntity } from '../profile/entities/profile.entity';
import { FoodLogEntity } from '../logs/entities/food-log.entity';
import { MeasurementEntity } from '../measurements/entities/measurement.entity';
import { PlanEntity } from '../plans/entities/plan.entity';
import { SubscriptionEntity } from '../billing/entities/subscription.entity';
import { UserEntity } from '../users/infrastructure/persistence/relational/entities/user.entity';
import { HealthProfileEntity } from '../profile/entities/health-profile.entity';
import { ConsentEntity } from '../profile/entities/consent.entity';

export interface ClientSummary {
  user_id: number;
  name: string;
  goal: string;
  goal_declared: string | null;
  food_preference: string;
  tier: string;
  days_on_plan: number;
  weight_kg: number;
  goal_weight_kg: number | null;
  /// The most recent day with anything logged. The roster sorts on this rather than on how long
  /// they have been a member: opening on the oldest account shows an empty week and makes a working
  /// dashboard look broken.
  last_logged_date: string | null;
  /// `+9199…8833`. Enough to recognise a row and match it to a ticket, not enough to dial or to
  /// harvest — docs/13 §4 asks for masking in list views, and a blank column made the roster
  /// unscannable. The full number lives on the detail record, behind the reason and the audit row.
  phone_masked: string | null;
}

/**
 * Everything the person answered during onboarding.
 *
 * **`screenedEatingDisorder` is deliberately absent.** docs/10 §5.5: "No role can see the
 * eating-disorder screening answer except super_admin under a `safety_review` reason. It exists to
 * protect the user, not to inform commerce." Leaving it out of the type is stronger than filtering
 * it later — there is no shape of this object that can carry it.
 *
 * The other two screening answers ARE here: they are eligibility gates the applicant was told about
 * (docs/05 §4) and an admin handling a support ticket about a blocked plan cannot resolve it
 * without seeing which gate fired.
 */
export interface RegistrationAnswers {
  sex_at_birth: string;
  goal_weight_kg: number | null;
  /// What the person PICKED, next to what the engine plans from. docs/03: they are different
  /// questions and the gap between them is worth seeing.
  goal_declared: string | null;
  meal_count: string;
  lifestyle: string;
  budget_tier: string;
  /// A rupee figure, distinct from the coarse `budget_tier` band. Both are asked; showing only the
  /// band loses the number the person actually typed.
  budget_monthly_inr: number | null;
  food_dislikes: string | null;
  wake_time: string | null;
  sleep_time: string | null;
  sleep_hours: number | null;
  /// docs/04 §7's five-to-six meal pattern, as the person said their day runs. The engine schedules
  /// against these, so an admin debugging "my plan says dinner at 8" needs to see what was entered.
  meal_times: {
    breakfast: string | null;
    mid_morning: string | null;
    lunch: string | null;
    evening_snack: string | null;
    dinner: string | null;
    bedtime_snack: string | null;
  };
  conditions: string[];
  allergies: string[];
  digestive_symptoms: string[];
  injuries: string[];
  medications: string | null;
  menstrual_regularity: string | null;
  pregnant_or_breastfeeding: boolean | null;
  heavy_bleeding_or_pain: boolean | null;
  hormonal_medication: boolean | null;
  screened_special_diet: boolean | null;
  screened_insulin_or_kidney: boolean | null;
  health_profile_version: number | null;
  /// What the server decided from the answers above (docs/05 §4). Stored rather than recomputed —
  /// this is the record of which gate fired and why a plan was or was not allowed.
  gates: Record<string, unknown> | null;
  consents: {
    type: string;
    granted: boolean;
    policy_version: string;
    granted_at: string;
  }[];
}

export interface ClientDetail extends ClientSummary {
  age_years: number;
  height_cm: number;
  activity: string;
  /// Contact details. On the DETAIL endpoint only, never the roster — docs/13 §4 names "full phone
  /// + email visible in admin list views" as a defect and asks for a reveal behind an audited
  /// action. This whole endpoint is that action: it needs a reason and writes a `read_health` row.
  ///
  /// docs/10 §5.1 bans a coach or partner from exporting client contact details. An ADMIN reading
  /// one person's number to answer their ticket is the audited read docs/10 §4 allows; a list of
  /// them would be the export §5.1 forbids, which is why this is one record at a time.
  phone: string | null;
  email: string | null;
  auth_provider: string | null;
  /// What they told us when they signed up. Health data, so this whole endpoint is behind a reason
  /// header and writes a `read_health` audit row.
  registration: RegistrationAnswers;
  /// Today's targets, from the stored plan. Never computed here — the engine owns that number
  /// (`api/CLAUDE.md` rule 2) and an admin screen recomputing it would be a second source of truth.
  targets: Record<string, number> | null;
  /// What they have actually eaten today, against those targets.
  today: {
    kcal: number;
    proteinG: number;
    carbG: number;
    fatG: number;
    entries: number;
  };
  /// Days logged out of the last 28, and the streak — the health equivalent of "days worked".
  adherence: {
    days_logged: number;
    window_days: number;
    pct: number;
    streak: number;
  };
  /// `cells[slotIndex][dayIndex]` over the last 7 days, bucketed 0..3 by how much was logged in
  /// that meal slot. Same shape the activity grid already renders.
  logging_grid: { slots: string[]; days: string[]; cells: number[][] };
  /// Most logged foods, by number of entries. The widget the reference spends on applications.
  top_foods: { name: string; entries: number; kcal: number; pct: number }[];
  /// Weight over time, oldest first.
  weight_series: { date: string; kg: number }[];
  /// What was eaten, by slot, for the last 7 days — the calendar's rows.
  recent_meals: { date: string; slot: string; name: string; kcal: number }[];
}

/// Four buckets, like the reference's legend. Measured in entries per slot, because "did they log
/// this meal" is the question an adherence grid answers.
function bucket(kcal: number): number {
  if (kcal <= 0) return 0;
  if (kcal < 200) return 1;
  if (kcal < 400) return 2;
  return 3;
}

/**
 * `+919933938833` -> `+9199…8833`.
 *
 * Keeps the country code and the last four — the two parts a human uses to recognise a number they
 * already know. Everything in between is what makes it dialable, and that is the part docs/13 §4
 * asks to hide in a list. A number too short to mask meaningfully is hidden entirely rather than
 * shown with a token gap.
 */
export function maskPhone(phone: string | null): string | null {
  if (!phone) return null;
  const trimmed = phone.trim();
  if (trimmed.length < 8) return '••••';
  return `${trimmed.slice(0, 4)}…${trimmed.slice(-4)}`;
}

function isoDate(daysAgo: number): string {
  const d = new Date();
  d.setUTCDate(d.getUTCDate() - daysAgo);
  return d.toISOString().slice(0, 10);
}

/**
 * The client-facing half of the admin dashboard.
 *
 * Everything here is a diary, a plan or a weight — the things Eatzify actually holds. The widgets
 * map one for one onto the reference's layout, which is the point: the SHAPE of an operations
 * dashboard is not domain-specific, only its content is.
 *
 * Reading a client's diary is reading health data, so `AdminController` writes a `read_health` audit
 * row with a reason before this returns anything (docs/10 §4).
 */
@Injectable()
export class AdminClientsService {
  constructor(
    @InjectRepository(ProfileEntity)
    private readonly profiles: Repository<ProfileEntity>,
    @InjectRepository(FoodLogEntity)
    private readonly logs: Repository<FoodLogEntity>,
    @InjectRepository(MeasurementEntity)
    private readonly measurements: Repository<MeasurementEntity>,
    @InjectRepository(PlanEntity)
    private readonly plans: Repository<PlanEntity>,
    @InjectRepository(SubscriptionEntity)
    private readonly subscriptions: Repository<SubscriptionEntity>,
    @InjectRepository(UserEntity)
    private readonly users: Repository<UserEntity>,
    @InjectRepository(HealthProfileEntity)
    private readonly healthProfiles: Repository<HealthProfileEntity>,
    @InjectRepository(ConsentEntity)
    private readonly consents: Repository<ConsentEntity>,
  ) {}

  async list(limit = 50): Promise<ClientSummary[]> {
    const rows = await this.profiles.find({
      order: { id: 'ASC' },
      take: Math.min(limit, 200),
    });

    const subs = await this.subscriptions.find();
    const tierOf = new Map(subs.map((s) => [s.userId, s.tier]));

    // One query for the page rather than one per row.
    const users = await this.users.find({
      where: rows.map((r) => ({ id: r.userId })),
    });
    const phoneOf = new Map(users.map((u) => [u.id, u.phone ?? null]));

    return Promise.all(
      rows.map(async (p) => ({
        user_id: p.userId,
        name: p.name ?? `Client ${p.userId}`,
        goal: p.goal,
        goal_declared: p.goalDeclared,
        food_preference: p.foodPreference,
        tier: tierOf.get(p.userId) ?? 'FREE',
        days_on_plan: await this.daysOnPlan(p.userId),
        weight_kg: Number(p.weightKg),
        goal_weight_kg: p.goalWeightKg === null ? null : Number(p.goalWeightKg),
        last_logged_date: await this.lastLogged(p.userId),
        phone_masked: maskPhone(phoneOf.get(p.userId) ?? null),
      })),
    );
  }

  async detail(userId: number): Promise<ClientDetail> {
    const profile = await this.profiles.findOne({ where: { userId } });
    if (!profile)
      throw new NotFoundException({ error: { code: 'CLIENT_NOT_FOUND' } });

    const [summary] = await this.list(200).then((all) =>
      all.filter((c) => c.user_id === userId),
    );

    const since = isoDate(27);
    const entries = await this.logs
      .createQueryBuilder('l')
      .leftJoinAndSelect('l.food', 'food')
      .where('l.userId = :userId', { userId })
      .andWhere('l.diaryDate >= :since', { since })
      .orderBy('l.diaryDate', 'DESC')
      .getMany();

    const plan = await this.plans.findOne({
      where: { userId },
      order: { planDate: 'DESC' },
    });

    const weights = await this.measurements.find({
      where: { userId, kind: 'weight' },
      order: { diaryDate: 'ASC' },
    });

    const today = isoDate(0);
    const todayRows = entries.filter((e) => e.diaryDate === today);

    // Days logged in the window, and the run of consecutive days ending today.
    const loggedDays = new Set(entries.map((e) => e.diaryDate));
    let streak = 0;
    for (let d = 0; d < 28; d += 1) {
      if (!loggedDays.has(isoDate(d))) break;
      streak += 1;
    }

    const slots = ['breakfast', 'mid_morning', 'lunch', 'snack', 'dinner'];
    const days = Array.from({ length: 7 }, (_, i) => isoDate(6 - i));
    const cells = slots.map((slot) =>
      days.map((date) =>
        bucket(
          entries
            .filter((e) => e.diaryDate === date && e.slot === slot)
            .reduce((sum, e) => sum + Number(e.kcal), 0),
        ),
      ),
    );

    const byFood = new Map<string, { entries: number; kcal: number }>();
    for (const e of entries) {
      const name = e.food?.name ?? e.customName ?? 'Custom entry';
      const current = byFood.get(name) ?? { entries: 0, kcal: 0 };
      byFood.set(name, {
        entries: current.entries + 1,
        kcal: current.kcal + Number(e.kcal),
      });
    }
    const topFoods = [...byFood.entries()]
      .sort((a, b) => b[1].entries - a[1].entries)
      .slice(0, 5)
      .map(([name, v]) => ({
        name,
        entries: v.entries,
        kcal: Math.round(v.kcal),
        pct:
          entries.length === 0
            ? 0
            : Math.round((v.entries / entries.length) * 100),
      }));

    // Latest version wins: `health_profile` is versioned and merged forward on every edit (D-33).
    const health = await this.healthProfiles.findOne({
      where: { userId },
      order: { version: 'DESC' },
    });

    const consents = await this.consents.find({
      where: { userId },
      order: { grantedAt: 'DESC' },
    });

    const user = await this.users.findOne({ where: { id: userId } });

    return {
      ...summary,
      age_years: profile.ageYears,
      height_cm: profile.heightCm,
      activity: profile.activity,
      phone: user?.phone ?? null,
      email: user?.email ?? null,
      auth_provider: user?.provider ?? null,
      registration: {
        sex_at_birth: profile.sexAtBirth,
        goal_weight_kg:
          profile.goalWeightKg === null ? null : Number(profile.goalWeightKg),
        goal_declared: profile.goalDeclared,
        meal_count: profile.mealCount,
        lifestyle: profile.lifestyle,
        budget_tier: profile.budgetTier,
        budget_monthly_inr:
          profile.budgetMonthlyInr === null ||
          profile.budgetMonthlyInr === undefined
            ? null
            : Number(profile.budgetMonthlyInr),
        food_dislikes: profile.foodDislikes ?? null,
        wake_time: profile.wakeTime,
        sleep_time: profile.sleepTime,
        sleep_hours:
          profile.sleepHours === null ? null : Number(profile.sleepHours),
        meal_times: {
          breakfast: profile.breakfastTime ?? null,
          mid_morning: profile.midMorningTime ?? null,
          lunch: profile.lunchTime ?? null,
          evening_snack: profile.eveningSnackTime ?? null,
          dinner: profile.dinnerTime ?? null,
          bedtime_snack: profile.bedtimeSnackTime ?? null,
        },
        conditions: health?.conditions ?? [],
        allergies: health?.allergies ?? [],
        digestive_symptoms: health?.digestiveSymptoms ?? [],
        injuries: health?.injuries ?? [],
        medications: health?.medications ?? null,
        menstrual_regularity: health?.menstrualRegularity ?? null,
        pregnant_or_breastfeeding: health?.pregnantOrBreastfeeding ?? null,
        heavy_bleeding_or_pain: health?.heavyBleedingOrPain ?? null,
        hormonal_medication: health?.hormonalMedication ?? null,
        screened_special_diet: health?.screenedSpecialDiet ?? null,
        screened_insulin_or_kidney: health?.screenedInsulinOrKidney ?? null,
        health_profile_version: health?.version ?? null,
        gates: (health?.gates as Record<string, unknown> | undefined) ?? null,
        consents: consents.map((c) => ({
          type: c.type,
          granted: c.granted,
          policy_version: c.policyVersion,
          granted_at: c.grantedAt.toISOString(),
        })),
      },
      targets: plan?.targets ?? null,
      today: {
        kcal: Math.round(todayRows.reduce((s, e) => s + Number(e.kcal), 0)),
        proteinG: Math.round(
          todayRows.reduce((s, e) => s + Number(e.proteinG), 0),
        ),
        carbG: Math.round(todayRows.reduce((s, e) => s + Number(e.carbG), 0)),
        fatG: Math.round(todayRows.reduce((s, e) => s + Number(e.fatG), 0)),
        entries: todayRows.length,
      },
      adherence: {
        days_logged: loggedDays.size,
        window_days: 28,
        pct: Math.round((loggedDays.size / 28) * 100),
        streak,
      },
      logging_grid: { slots, days, cells },
      top_foods: topFoods,
      weight_series: weights.map((w) => ({
        date: w.diaryDate,
        kg: Number(w.value),
      })),
      recent_meals: entries
        .filter((e) => days.includes(e.diaryDate))
        .slice(0, 40)
        .map((e) => ({
          date: e.diaryDate,
          slot: e.slot,
          name: e.food?.name ?? e.customName ?? 'Custom entry',
          kcal: Math.round(Number(e.kcal)),
        })),
    };
  }

  private async lastLogged(userId: number): Promise<string | null> {
    const last = await this.logs.findOne({
      where: { userId },
      order: { diaryDate: 'DESC' },
    });
    return last?.diaryDate ?? null;
  }

  /// Days since the first thing they ever logged. The health answer to "days in company".
  private async daysOnPlan(userId: number): Promise<number> {
    const first = await this.logs.findOne({
      where: { userId },
      order: { diaryDate: 'ASC' },
    });
    if (!first) return 0;
    const ms = Date.now() - new Date(first.diaryDate).getTime();
    return Math.max(0, Math.floor(ms / 86_400_000));
  }
}
