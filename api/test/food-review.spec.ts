import { type DataSource, type Repository } from 'typeorm';
import { FoodsService } from '../src/foods/foods.service';
import { FoodEntity, type FoodStatus } from '../src/foods/entities/food.entity';

/// docs/08 §4 and docs/09 §9. A food moves draft → reviewed → published, and somebody's name is
/// against each step — its macros end up in a person's plan.

const NOW = new Date('2026-09-18T10:00:00Z');
const ADMIN = 3;
const OTHER_ADMIN = 4;

type Row = Partial<FoodEntity>;

/// The columns the CSV importer accepts, which is also what `POST /admin/foods` takes.
const validRow = {
  name: 'Poha',
  nameHi: 'पोहा',
  aliases: 'pohe',
  kcal: '180',
  proteinG: '4',
  fatG: '5',
  carbG: '30',
  fibreG: '2',
  sodiumMg: '210',
  addedSugarG: '1',
  saturatedFatG: '1',
  tags: 'meal:breakfast',
  suitableFor: 'veg',
  allergens: '',
  costTier: 'low',
  source: 'manual',
  sourceRef: '',
  measures: 'katori=150',
};

function serviceWith(rows: Row[] = []) {
  const foods = {
    rows,
    create: (row: Row) => row,
    save: (row: Row) => {
      const at = rows.findIndex((r) => r.id && r.id === row.id);
      const saved = { id: row.id ?? `f${rows.length + 1}`, ...row };
      if (at >= 0) rows[at] = saved;
      else rows.push(saved);
      return Promise.resolve(saved);
    },
    findOne: ({ where }: { where: { id?: string } }) =>
      Promise.resolve(rows.find((r) => r.id === where.id) ?? null),
    find: ({ where }: { where?: { status?: FoodStatus } } = {}) =>
      Promise.resolve(
        rows.filter((r) => !where?.status || r.status === where.status),
      ),
    update: (criteria: unknown, patch: Row) => {
      const ids = Array.isArray(criteria) ? criteria : null;
      let affected = 0;
      for (const row of rows) {
        const hit = ids ? ids.includes(row.id!) : row.isVerified === false;
        if (!hit) continue;
        Object.assign(row, patch);
        affected++;
      }
      return Promise.resolve({ affected });
    },
  } as unknown as Repository<FoodEntity>;

  return {
    service: new FoodsService(foods, {} as unknown as DataSource),
    rows,
  };
}

async function refusedCode(run: Promise<unknown>): Promise<string> {
  try {
    await run;
  } catch (e) {
    const body = (
      e as { getResponse(): { error: { code: string } } }
    ).getResponse();
    return body.error.code;
  }
  throw new Error('expected the call to be refused');
}

describe('typing a food in (docs/09 §9)', () => {
  it('should save it as a draft, never as something a plan can use', async () => {
    const { service, rows } = serviceWith();

    const saved = await service.createDraft(validRow);

    expect(saved).toMatchObject({
      name: 'Poha',
      status: 'draft',
      isVerified: false,
    });
    expect(rows).toHaveLength(1);
  });

  it('should hold it to the same rules as the CSV importer', async () => {
    const { service, rows } = serviceWith();

    expect(
      await refusedCode(service.createDraft({ ...validRow, kcal: 'nonsense' })),
    ).toBe('FOOD_INVALID');
    expect(rows).toEqual([]);
  });
});

describe('the review steps (docs/08 §4)', () => {
  const draft: Row = {
    id: 'f1',
    name: 'Poha',
    status: 'draft',
    isVerified: false,
  };

  it('should record who reviewed it, and when', async () => {
    const { service, rows } = serviceWith([{ ...draft }]);

    await service.review('f1', ADMIN, NOW);

    expect(rows[0]).toMatchObject({
      status: 'reviewed',
      reviewedByUserId: ADMIN,
      reviewedAt: NOW,
      // Still not live: a reviewed food is not a published one.
      isVerified: false,
    });
  });

  it('should publish only from reviewed, and say so otherwise', async () => {
    const { service, rows } = serviceWith([{ ...draft }]);

    expect(await refusedCode(service.publish('f1', ADMIN, NOW))).toBe(
      'FOOD_STEP_NOT_ALLOWED',
    );

    await service.review('f1', ADMIN, NOW);
    await service.publish('f1', OTHER_ADMIN, NOW);

    expect(rows[0]).toMatchObject({
      status: 'published',
      isVerified: true,
      reviewedByUserId: ADMIN,
      publishedByUserId: OTHER_ADMIN,
      publishedAt: NOW,
    });
  });

  it('should refuse to review something that is already published', async () => {
    const { service } = serviceWith([
      { id: 'f1', status: 'published', isVerified: true },
    ]);

    expect(await refusedCode(service.review('f1', ADMIN, NOW))).toBe(
      'FOOD_STEP_NOT_ALLOWED',
    );
  });

  /// docs/08 §4: nothing is deleted — the row is in somebody's diary.
  it('should retire a food out of circulation without removing it', async () => {
    const { service, rows } = serviceWith([
      { id: 'f1', status: 'published', isVerified: true },
    ]);

    await service.retire('f1', ADMIN, NOW);

    expect(rows).toHaveLength(1);
    expect(rows[0]).toMatchObject({ status: 'retired', isVerified: false });
  });

  it('should say when the food is not there at all', async () => {
    const { service } = serviceWith();

    await expect(service.publish('missing', ADMIN, NOW)).rejects.toMatchObject({
      status: 404,
    });
  });

  it('should list what is waiting at each step', async () => {
    const { service } = serviceWith([
      { id: 'f1', status: 'draft' },
      { id: 'f2', status: 'reviewed' },
      { id: 'f3', status: 'published' },
    ]);

    expect((await service.byStatus('reviewed')).map((f) => f.id)).toEqual([
      'f2',
    ]);
  });
});

/// The old path still exists; it must not be able to disagree with the new one.
describe('the verify shortcut', () => {
  it('should set the status as well as the flag', async () => {
    const { service, rows } = serviceWith([
      { id: 'f1', status: 'draft', isVerified: false },
    ]);

    await service.verify(['f1']);

    expect(rows[0]).toMatchObject({ status: 'published', isVerified: true });
  });
});
