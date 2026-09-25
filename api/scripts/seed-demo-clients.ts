/**
 * Demo clients for the admin dashboard.
 *
 * Eatzify is a diet platform, so the dashboard's figures have to come from diaries, plans and
 * weights — not from an HR system. Nothing in the database could populate those screens, because
 * the only seeded users are the boilerplate's admin and test accounts with no health data at all.
 *
 * **Everything written here is marked.** Every user's email ends `@demo.eatzify.test` and every
 * profile name is prefixed `[demo]`, so one query finds all of it and `--purge` removes it. docs/08
 * §10 asks for an `is_demo` column for exactly this and the schema has none (D-180); a reserved
 * email domain is the honest substitute until it does.
 *
 * Refuses to run against anything but a local database. docs/08 §10: "the production deploy pipeline
 * refuses to run any seeder", and a seeder that only refuses in the pipeline is one `psql` away from
 * inventing 8 clients in production.
 *
 *   npx ts-node scripts/seed-demo-clients.ts
 *   npx ts-node scripts/seed-demo-clients.ts --purge
 */
import 'reflect-metadata';
import { AppDataSource } from '../src/database/data-source';
import { UserEntity } from '../src/users/infrastructure/persistence/relational/entities/user.entity';
import { ProfileEntity } from '../src/profile/entities/profile.entity';
import { PlanEntity } from '../src/plans/entities/plan.entity';
import { FoodLogEntity } from '../src/logs/entities/food-log.entity';
import { FoodEntity } from '../src/foods/entities/food.entity';
import { MeasurementEntity } from '../src/measurements/entities/measurement.entity';
import { SubscriptionEntity } from '../src/billing/entities/subscription.entity';
import { CoachApplicationEntity } from '../src/coach/entities/coach-application.entity';
import { HealthProfileEntity } from '../src/profile/entities/health-profile.entity';
import { ConsentEntity } from '../src/profile/entities/consent.entity';
import { RoleEnum } from '../src/roles/roles.enum';
import { StatusEnum } from '../src/statuses/statuses.enum';

const DEMO_DOMAIN = '@demo.eatzify.test';

/**
 * A number for a seeded account, so the admin queue's masked-phone column has something to mask.
 *
 * `+9190000000NN`, the same synthetic block the specs use. `.claude/rules/api-testing.md` forbids a
 * real number in a fixture, and an admin screen whose phone column is always blank cannot be told
 * apart from one that is broken — which is exactly how it was read.
 */
function demoPhone(index: number): string {
  return `+9190000${String(index).padStart(5, '0')}`;
}
const DEMO_PREFIX = '[demo] ';

/// Deterministic, so re-running produces the same dashboard and a screenshot from yesterday still
/// matches. `Math.random()` in a seeder makes every bug report unreproducible.
function rng(seed: number): () => number {
  let s = seed;
  return () => {
    s = (s * 1664525 + 1013904223) % 4294967296;
    return s / 4294967296;
  };
}

/// A stable uuid per applicant and slot. These point at nothing — the file service is not wired —
/// but the COLUMN's meaning is "a document is on file", and seeding null while claiming `submitted`
/// describes a state the API would never produce.
function fakeFileId(name: string, slot: string): string {
  let h = 0;
  for (const ch of `${name}:${slot}`) h = (h * 31 + ch.charCodeAt(0)) >>> 0;
  const hex = h.toString(16).padStart(8, '0');
  return `${hex}-0000-4000-8000-${hex}0000`;
}

function isoDate(daysAgo: number): string {
  const d = new Date();
  d.setUTCDate(d.getUTCDate() - daysAgo);
  return d.toISOString().slice(0, 10);
}

/// Partner applicants, one per discipline and status combination worth seeing on the dashboard.
/// `joinedDaysAgo` doubles as how long a submitted application has been waiting.
const APPLICANTS = [
  {
    name: 'Dr Neha Bhatia',
    discipline: 'doctor',
    status: 'submitted',
    daysAgo: 6,
  },
  {
    name: 'Ishaan Verma',
    discipline: 'trainer',
    status: 'submitted',
    daysAgo: 3,
  },
  {
    name: 'Ritu Agarwal',
    discipline: 'nutritionist',
    status: 'submitted',
    daysAgo: 1,
  },
  {
    name: 'Sameer Khan',
    discipline: 'trainer',
    status: 'verified',
    daysAgo: 40,
  },
  {
    name: 'Dr Anil Kapoor',
    discipline: 'doctor',
    status: 'verified',
    daysAgo: 28,
  },
  {
    name: 'Pooja Desai',
    discipline: 'nutritionist',
    status: 'verified',
    daysAgo: 19,
  },
  {
    name: 'Manish Gupta',
    discipline: 'trainer',
    status: 'rejected',
    daysAgo: 12,
  },
  { name: 'Farah Shaikh', discipline: 'other', status: 'draft', daysAgo: 2 },
] as const;

const CLIENTS = [
  {
    name: 'Ananya Iyer',
    age: 29,
    heightCm: 163,
    weightKg: 71.4,
    goalWeightKg: 62,
    sex: 'female',
    goal: 'fat_loss',
    goalDeclared: 'weight_loss',
    activity: 'light',
    pref: 'veg',
    tier: 'PRO',
    joinedDaysAgo: 412,
    conditions: ['pcos'],
    allergies: ['peanut'],
    digestive: ['bloating'],
  },
  {
    name: 'Rahul Mehta',
    age: 34,
    heightCm: 176,
    weightKg: 84.2,
    goalWeightKg: 76,
    sex: 'male',
    goal: 'fat_loss',
    goalDeclared: 'fat_loss',
    activity: 'moderate',
    pref: 'non_veg',
    tier: 'PRO',
    joinedDaysAgo: 286,
    conditions: ['prediabetes'],
    allergies: [],
    digestive: ['acidity'],
  },
  {
    name: 'Priya Nair',
    age: 26,
    heightCm: 158,
    weightKg: 52.1,
    goalWeightKg: 56,
    sex: 'female',
    goal: 'muscle_gain',
    goalDeclared: 'muscle_gain',
    activity: 'active',
    pref: 'eggetarian',
    tier: 'BASIC',
    joinedDaysAgo: 154,
    conditions: ['none'],
    allergies: ['milk'],
    digestive: ['none'],
  },
  {
    name: 'Vikram Singh',
    age: 41,
    heightCm: 171,
    weightKg: 92.8,
    goalWeightKg: 80,
    sex: 'male',
    goal: 'fat_loss',
    goalDeclared: 'medical_support',
    activity: 'sedentary',
    pref: 'non_veg',
    tier: 'PRO',
    joinedDaysAgo: 98,
    conditions: ['type2_diabetes', 'hypertension'],
    allergies: [],
    digestive: ['none'],
  },
  {
    name: 'Sneha Kulkarni',
    age: 31,
    heightCm: 160,
    weightKg: 64.5,
    goalWeightKg: 58,
    sex: 'female',
    goal: 'fat_loss',
    goalDeclared: 'weight_loss',
    activity: 'light',
    pref: 'jain',
    tier: 'BASIC',
    joinedDaysAgo: 67,
    conditions: ['hypothyroid'],
    allergies: ['soy'],
    digestive: ['constipation'],
  },
  {
    name: 'Arjun Reddy',
    age: 24,
    heightCm: 180,
    weightKg: 68.3,
    goalWeightKg: 76,
    sex: 'male',
    goal: 'muscle_gain',
    goalDeclared: 'muscle_gain',
    activity: 'very_active',
    pref: 'non_veg',
    tier: 'FREE',
    joinedDaysAgo: 43,
    conditions: ['none'],
    allergies: [],
    digestive: ['none'],
  },
  {
    name: 'Meera Joshi',
    age: 38,
    heightCm: 156,
    weightKg: 59.7,
    goalWeightKg: 55,
    sex: 'female',
    goal: 'maintenance',
    goalDeclared: 'general_fitness',
    activity: 'moderate',
    pref: 'vegan',
    tier: 'BASIC',
    joinedDaysAgo: 21,
    conditions: ['high_cholesterol'],
    allergies: ['tree_nut'],
    digestive: ['gas'],
  },
  {
    name: 'Karthik Rao',
    age: 45,
    heightCm: 169,
    weightKg: 88.1,
    goalWeightKg: 78,
    sex: 'male',
    goal: 'fat_loss',
    goalDeclared: 'medical_support',
    activity: 'sedentary',
    pref: 'veg',
    tier: 'FREE',
    joinedDaysAgo: 9,
    conditions: ['fatty_liver'],
    allergies: [],
    digestive: ['acidity'],
  },
];

/// Slots and the share of the day's energy each carries. docs/04 §7's pattern, roughly — enough for
/// a diary that looks like a person ate, which is all this has to be.
const SLOT_SHARE: [string, number][] = [
  ['breakfast', 0.22],
  ['mid_morning', 0.08],
  ['lunch', 0.32],
  ['snack', 0.1],
  ['dinner', 0.28],
];

async function purge(): Promise<void> {
  const users = await AppDataSource.getRepository(UserEntity)
    .createQueryBuilder('u')
    .where('u.email LIKE :d', { d: `%${DEMO_DOMAIN}` })
    .getMany();

  if (users.length === 0) {
    console.log('Nothing to purge.');
    return;
  }

  const ids = users.map((u) => u.id);
  // Children first: nothing here cascades, and a half-deleted client is worse than none.
  for (const [entity, column] of [
    [CoachApplicationEntity, 'userId'],
    [ConsentEntity, 'userId'],
    [HealthProfileEntity, 'userId'],
    [FoodLogEntity, 'userId'],
    [MeasurementEntity, 'userId'],
    [PlanEntity, 'userId'],
    [SubscriptionEntity, 'userId'],
    [ProfileEntity, 'userId'],
  ] as const) {
    await AppDataSource.getRepository(entity as never)
      .createQueryBuilder()
      .delete()
      .where(`"${column}" IN (:...ids)`, { ids })
      .execute();
  }
  await AppDataSource.getRepository(UserEntity).delete(ids);
  console.log(
    `Purged ${users.length} demo clients and everything attached to them.`,
  );
}

/// The partner pipeline. Written directly rather than through the service so a row can be seeded in
/// any state — the service deliberately refuses to fabricate a `verified` one (that needs a human).
async function seedApplicants(): Promise<void> {
  const users = AppDataSource.getRepository(UserEntity);
  const applications = AppDataSource.getRepository(CoachApplicationEntity);

  for (const a of APPLICANTS) {
    const email = `${a.name.toLowerCase().replace(/[^a-z]+/g, '.')}${DEMO_DOMAIN}`;

    let user = await users.findOne({ where: { email } });
    if (!user) {
      user = await users.save(
        users.create({
          email,
          phone: demoPhone(APPLICANTS.indexOf(a)),
          firstName: a.name.split(' ')[0],
          lastName: a.name.split(' ').slice(1).join(' '),
          // Level 1 on agreement, level 2 once verified — docs/12 §6.
          role: {
            id: a.status === 'verified' ? RoleEnum.coach_l2 : RoleEnum.coach_l1,
          },
          status: { id: StatusEnum.active },
        }),
      );
    } else if (!user.phone) {
      // Re-running must repair an account seeded before this column was filled, or the fix only
      // ever reaches a database nobody has created yet.
      user.phone = demoPhone(APPLICANTS.indexOf(a));
      await users.save(user);
    }

    if (await applications.findOne({ where: { userId: user.id } })) continue;

    const submitted =
      a.status === 'draft' ? null : new Date(`${isoDate(a.daysAgo)}T09:00:00Z`);

    await applications.save(
      applications.create({
        userId: user.id,
        status: a.status,
        discipline: a.discipline,
        agreementAcceptedAt: new Date(`${isoDate(a.daysAgo + 1)}T09:00:00Z`),
        agreementVersion: 'v1',
        // A draft has not handed its documents over yet; everything else has, because `submit()`
        // refuses without both (docs/12 §6). Deterministic uuids so re-seeding is idempotent.
        idDocumentFileId: a.status === 'draft' ? null : fakeFileId(a.name, 'id'),
        qualificationDocumentFileId:
          a.status === 'draft' ? null : fakeFileId(a.name, 'qualification'),
        submittedAt: submitted,
        reviewedAt:
          a.status === 'verified' || a.status === 'rejected'
            ? new Date(`${isoDate(Math.max(0, a.daysAgo - 1))}T09:00:00Z`)
            : null,
        // Reviewed by the seeded admin, so the audit trail has a real actor.
        reviewedByUserId:
          a.status === 'verified' || a.status === 'rejected' ? 1 : null,
        verifiedAttributes:
          a.status === 'verified'
            ? a.discipline === 'doctor'
              ? ['government_id', 'medical_licence']
              : a.discipline === 'nutritionist'
                ? ['government_id', 'dietetics_degree']
                : ['government_id', 'training_certification']
            : [],
        rejectionReason:
          a.status === 'rejected'
            ? 'The qualification document was unreadable.'
            : null,
      }),
    );

    console.log(
      `  ${a.name.padEnd(18)} ${a.discipline.padEnd(13)} ${a.status}`,
    );
  }
}

async function seed(): Promise<void> {
  const users = AppDataSource.getRepository(UserEntity);
  const profiles = AppDataSource.getRepository(ProfileEntity);
  const plans = AppDataSource.getRepository(PlanEntity);
  const logs = AppDataSource.getRepository(FoodLogEntity);
  const measurements = AppDataSource.getRepository(MeasurementEntity);
  const subscriptions = AppDataSource.getRepository(SubscriptionEntity);
  const healthProfiles = AppDataSource.getRepository(HealthProfileEntity);
  const consents = AppDataSource.getRepository(ConsentEntity);

  // Real rows from the imported food database (D-40), so the diary references food that exists and
  // the dashboard's "most logged" list reads like Indian home cooking rather than lorem ipsum.
  const foods = await AppDataSource.getRepository(FoodEntity)
    .createQueryBuilder('f')
    .orderBy('f.name', 'ASC')
    .limit(60)
    .getMany();

  if (foods.length === 0) {
    throw new Error(
      'The food table is empty. Run the food import first — the diary has to reference real food.',
    );
  }

  for (const [index, c] of CLIENTS.entries()) {
    const email = `${c.name.toLowerCase().replace(/[^a-z]+/g, '.')}${DEMO_DOMAIN}`;

    let user = await users.findOne({ where: { email } });
    if (!user) {
      user = await users.save(
        users.create({
          email,
          // Offset past the applicants so no two demo accounts share a number.
          phone: demoPhone(100 + index),
          firstName: c.name.split(' ')[0],
          lastName: c.name.split(' ')[1],
          role: { id: RoleEnum.user },
          status: { id: StatusEnum.active },
        }),
      );
    } else if (!user.phone) {
      user.phone = demoPhone(100 + index);
      await users.save(user);
    }

    const existingProfile = await profiles.findOne({
      where: { userId: user.id },
    });
    if (!existingProfile) {
      await profiles.save(
        profiles.create({
          userId: user.id,
          ageYears: c.age,
          heightCm: c.heightCm,
          weightKg: c.weightKg.toFixed(2),
          goalWeightKg: c.goalWeightKg.toFixed(2),
          sexAtBirth: c.sex,
          goal: c.goal,
          goalDeclared: c.goalDeclared,
          activity: c.activity,
          foodPreference: c.pref,
          mealCount: '3_meals_2_snacks',
          lifestyle: 'desk_job',
          budgetTier: 'medium',
          name: `${DEMO_PREFIX}${c.name}`,
          // The rest of onboarding, so the admin's Registration tab has something to show.
          wakeTime: '06:45',
          sleepTime: '23:15',
          sleepHours: '7.5',
          breakfastTime: '08:15',
          midMorningTime: '11:00',
          lunchTime: '13:30',
          eveningSnackTime: '17:00',
          dinnerTime: '20:30',
          bedtimeSnackTime: c.tier === 'PRO' ? '22:30' : null,
          foodDislikes: c.pref === 'jain' ? 'Onion, garlic, root vegetables' : 'Bitter gourd',
          // The rupee figure behind the coarse band — both are asked at onboarding.
          budgetMonthlyInr:
            c.tier === 'PRO' ? 12000 : c.tier === 'BASIC' ? 7000 : 4000,
        }),
      );
    }

    // Versioned, merged forward on every edit (D-33) — v1 is what they answered at signup.
    if (!(await healthProfiles.findOne({ where: { userId: user.id } }))) {
      await healthProfiles.save(
        healthProfiles.create({
          userId: user.id,
          version: 1,
          conditions: [...c.conditions],
          allergies: [...c.allergies],
          digestiveSymptoms: [...c.digestive],
          injuries: [],
          medications: c.conditions.includes('type2_diabetes') ? 'Metformin 500mg' : null,
          screenedSpecialDiet: false,
          screenedInsulinOrKidney: false,
          // docs/10 §5.5 puts this beyond every role in the admin surface. Seeded false so the
          // column is not null, never surfaced.
          screenedEatingDisorder: false,
          pregnantOrBreastfeeding: c.sex === 'female' ? false : null,
          menstrualRegularity: c.sex === 'female' ? 'regular' : null,
          heavyBleedingOrPain: c.sex === 'female' ? false : null,
          hormonalMedication: c.sex === 'female' ? false : null,
        }),
      );
    }

    if ((await consents.count({ where: { userId: user.id } })) === 0) {
      await consents.save(
        ['terms', 'privacy', 'health_data_processing'].map((type) =>
          consents.create({
            userId: user.id,
            type,
            granted: true,
            policyVersion: '1.0.0',
          }),
        ),
      );
    }

    // Targets are stored, not computed here — CLAUDE.md rule 2 keeps the engine the only thing that
    // decides a calorie number. These are plausible stand-ins for a plan the engine would produce.
    const kcal =
      c.goal === 'muscle_gain' ? 2550 : c.goal === 'maintenance' ? 1950 : 1720;
    const targets = {
      kcal,
      proteinG: Math.round((kcal * 0.28) / 4),
      carbG: Math.round((kcal * 0.45) / 4),
      fatG: Math.round((kcal * 0.27) / 9),
      fibreG: 28,
    };

    const planDate = isoDate(0);
    if (!(await plans.findOne({ where: { userId: user.id, planDate } }))) {
      await plans.save(
        plans.create({
          userId: user.id,
          planDate,
          rulePackVersion: '1.0.0',
          healthProfileVersion: 1,
          targets,
          mealTargets: [],
          meals: [],
        }),
      );
    }

    const random = rng(1000 + index * 37);

    // 28 days of diary. Adherence varies per client and tails off at weekends, so the activity
    // heatmap has the texture of a real person rather than a solid block.
    if ((await logs.count({ where: { userId: user.id } })) === 0) {
      const rows: FoodLogEntity[] = [];
      const adherence = 0.55 + random() * 0.4;

      for (let day = 0; day < 28; day += 1) {
        const date = isoDate(day);
        const isWeekend = [0, 6].includes(new Date(date).getUTCDay());
        if (random() > adherence * (isWeekend ? 0.65 : 1)) continue;

        for (const [slot, share] of SLOT_SHARE) {
          if (random() > 0.85) continue;
          const food = foods[Math.floor(random() * foods.length)];
          const slotKcal = Math.round(
            targets.kcal * share * (0.8 + random() * 0.4),
          );

          rows.push(
            logs.create({
              userId: user.id,
              diaryDate: date,
              slot,
              foodId: food.id,
              quantityG: (80 + Math.round(random() * 180)).toFixed(1),
              measureLabel: 'katori',
              kcal: slotKcal.toFixed(1),
              proteinG: Math.round((slotKcal * 0.26) / 4).toFixed(1),
              carbG: Math.round((slotKcal * 0.47) / 4).toFixed(1),
              fatG: Math.round((slotKcal * 0.27) / 9).toFixed(1),
              fibreG: (2 + random() * 5).toFixed(1),
              source: 'manual',
            }),
          );
        }
      }
      await logs.save(rows);
    }

    // Weight, trending towards the goal without ever arriving — real series do not.
    if ((await measurements.count({ where: { userId: user.id } })) === 0) {
      const span = Math.min(c.joinedDaysAgo, 84);
      const drift = (c.weightKg - c.goalWeightKg) * 0.35;
      const rows: MeasurementEntity[] = [];

      for (let week = 0; week * 7 <= span; week += 1) {
        const day = span - week * 7;
        const progress = span === 0 ? 0 : (span - day) / span;
        const noise = (random() - 0.5) * 0.6;
        rows.push(
          measurements.create({
            userId: user.id,
            kind: 'weight',
            value: (c.weightKg + drift * progress * -1 + noise).toFixed(2),
            unit: 'kg',
            diaryDate: isoDate(day),
            source: 'manual',
          }),
        );
      }
      await measurements.save(rows);
    }

    if (!(await subscriptions.findOne({ where: { userId: user.id } }))) {
      await subscriptions.save(
        subscriptions.create({
          userId: user.id,
          tier: c.tier,
          status: c.tier === 'FREE' ? 'none' : 'active',
        }),
      );
    }

    console.log(`  ${c.name.padEnd(18)} ${c.tier.padEnd(6)} ${email}`);
  }
}

async function main(): Promise<void> {
  const host = process.env.DATABASE_HOST ?? 'localhost';
  if (!['localhost', '127.0.0.1', 'postgres', 'db'].includes(host)) {
    throw new Error(
      `Refusing to seed demo data against "${host}". This script is for local databases only.`,
    );
  }

  await AppDataSource.initialize();
  try {
    if (process.argv.includes('--purge')) {
      await purge();
    } else {
      console.log('Seeding demo clients:');
      await seed();
      console.log('\nSeeding demo partner applicants:');
      await seedApplicants();
      console.log(
        '\nDone. Remove them with: npx ts-node scripts/seed-demo-clients.ts --purge',
      );
    }
  } finally {
    await AppDataSource.destroy();
  }
}

main().catch((e) => {
  console.error(e instanceof Error ? e.message : e);
  process.exit(1);
});
