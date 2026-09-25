import { FoodScanService } from '../src/foods/scan/food-scan.service';
import { mkdtemp, readdir, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import type { FoodVisionProvider } from '../src/foods/scan/food-vision.provider';
import { NOT_FOOD, type PlateEstimate } from '../src/foods/scan/plate-estimate';
import { ScanPolicyService } from '../src/foods/scan/scan-policy.service';

/// D-238. Who may scan a meal photo is the server's call, per tier, admin-edited; and a scan's
/// answer is checked against the food table before the app ever sees it.

const DAY = 24 * 60 * 60 * 1000;
const NOW = new Date('2026-09-19T08:00:00Z');

type Row = {
  tier: string;
  enabled: boolean;
  dailyLimit: number;
  requiresAd: boolean;
  trialDays: number | null;
  updatedAt: Date;
};

const policyFor = (over: Partial<Row> = {}): Row => ({
  tier: 'FREE',
  enabled: true,
  dailyLimit: 3,
  requiresAd: true,
  trialDays: 3,
  updatedAt: NOW,
  ...over,
});

const policyService = (opts: {
  tier?: string;
  policy?: Row | null;
  signedUpDaysAgo?: number;
  usedToday?: number;
  saved?: unknown[];
}) =>
  new ScanPolicyService(
    {
      findOneBy: () =>
        Promise.resolve(opts.policy === undefined ? policyFor() : opts.policy),
      save: (row: Row) => Promise.resolve(row),
    } as never,
    {
      count: () => Promise.resolve(opts.usedToday ?? 0),
      save: (row: unknown) => {
        opts.saved?.push(row);
        return Promise.resolve(row);
      },
    } as never,
    {
      findOne: () =>
        Promise.resolve({
          id: 7,
          createdAt: new Date(
            NOW.getTime() - (opts.signedUpDaysAgo ?? 1) * DAY,
          ),
        }),
    } as never,
    {
      entitlements: () => Promise.resolve({ tier: opts.tier ?? 'FREE' }),
    } as never,
  );

describe('ScanPolicyService.status', () => {
  it('should allow a new FREE user to scan behind an ad inside the trial', async () => {
    const status = await policyService({ signedUpDaysAgo: 1 }).status(7, NOW);

    expect(status.allowed).toBe(true);
    expect(status.requires_ad).toBe(true);
    expect(status.remaining_today).toBe(3);
  });

  it('should close the FREE window when the trial days have passed', async () => {
    const status = await policyService({ signedUpDaysAgo: 4 }).status(7, NOW);

    expect(status.allowed).toBe(false);
    expect(status.reason).toBe('trial_over');
  });

  it('should stop a paid tier at its daily limit', async () => {
    const status = await policyService({
      tier: 'BASIC',
      policy: policyFor({
        tier: 'BASIC',
        dailyLimit: 10,
        requiresAd: false,
        trialDays: null,
      }),
      usedToday: 10,
    }).status(7, NOW);

    expect(status.reason).toBe('limit_reached');
    expect(status.remaining_today).toBe(0);
  });

  it('should treat a tier with no policy row as closed, not open', async () => {
    const status = await policyService({ policy: null }).status(7, NOW);

    expect(status.reason).toBe('disabled');
  });
});

describe('ScanPolicyService.assertAllowed', () => {
  // assertAllowed reads the real clock, so a trial measured from the fixture's fixed NOW expires
  // as the calendar moves and the denial becomes `trial_over` instead. A tier with no trial is
  // what this test is about anyway: the ad, not the trial.
  const adTier = () => policyService({ policy: policyFor({ trialDays: null }) });

  it('should ask for the ad when the tier requires one and none was watched', async () => {
    await expect(adTier().assertAllowed(7, false)).rejects.toMatchObject({
      status: 403,
      response: { error: { code: 'AD_REQUIRED' } },
    });
    await expect(adTier().assertAllowed(7, true)).resolves.toBeDefined();
  });

  it('should send a disabled tier to the upgrade sheet', async () => {
    await expect(
      policyService({ policy: policyFor({ enabled: false }) }).assertAllowed(
        7,
        true,
      ),
    ).rejects.toMatchObject({
      status: 403,
      response: { error: { code: 'ENTITLEMENT_REQUIRED' } },
    });
  });

  it('should answer 429 with the limit when today is used up', async () => {
    await expect(
      policyService({
        policy: policyFor({ trialDays: null }),
        usedToday: 3,
      }).assertAllowed(7, true),
    ).rejects.toMatchObject({
      status: 429,
      response: { error: { code: 'SCAN_LIMIT_REACHED' } },
    });
  });
});

describe('ScanPolicyService.update', () => {
  it('should remove the trial window on null and keep fields that were not sent', async () => {
    const view = await policyService({}).update('FREE', { trial_days: null });

    expect(view.trial_days).toBeNull();
    expect(view.daily_limit).toBe(3);
    expect(view.requires_ad).toBe(true);
  });
});

describe('FoodScanService (D-240)', () => {
  const rice = {
    name: 'Rice (cooked white)',
    grams: 200,
    kcal: 252,
    protein_g: 5.4,
    carb_g: 56,
    fat_g: 0.6,
    fibre_g: 0.8,
    sodium_mg: 2,
    added_sugar_g: 0,
    saturated_fat_g: 0.2,
  };
  const dal = {
    ...rice,
    name: 'Dal tadka',
    grams: 180,
    kcal: 216,
    protein_g: 10.8,
    carb_g: 27,
    fat_g: 7.2,
    fibre_g: 5.4,
    sodium_mg: 540,
  };
  const plate: PlateEstimate = {
    isFood: true,
    dishName: 'Rice with dal tadka',
    confidence: 0.8,
    items: [rice, dal],
  };
  const photo = { mimetype: 'image/jpeg', buffer: Buffer.from('x') } as never;

  let dir: string;
  beforeEach(async () => {
    dir = await mkdtemp(join(tmpdir(), 'meal-photos-'));
    process.env.MEAL_PHOTO_DIR = dir;
  });
  afterEach(async () => {
    delete process.env.MEAL_PHOTO_DIR;
    await rm(dir, { recursive: true, force: true });
  });

  /// A scan row store in memory, and the entries "logged".
  const world = (vision: FoodVisionProvider | null) => {
    const rows = new Map<number, Record<string, unknown>>();
    const logged: Record<string, unknown>[] = [];
    const service = new FoodScanService(
      vision,
      {
        assertAllowed: () => Promise.resolve({}),
        record: (userId: number, scan: Record<string, unknown>) => {
          const id = rows.size + 1;
          rows.set(id, { id, userId, foodLogId: null, ...scan });
          return Promise.resolve(id);
        },
      } as never,
      {
        logEstimate: (userId: number, entry: Record<string, unknown>) => {
          logged.push({ userId, ...entry });
          return Promise.resolve({ id: 'log-1', ...entry });
        },
      } as never,
      {
        findOne: ({ where }: { where: { id: number; userId: number } }) => {
          const row = rows.get(where.id);
          return Promise.resolve(
            row && row.userId === where.userId ? row : null,
          );
        },
        update: (id: number, patch: Record<string, unknown>) => {
          rows.set(id, { ...rows.get(id), ...patch });
          return Promise.resolve();
        },
      } as never,
    );
    return { service, rows, logged };
  };

  const seeing = (estimate: PlateEstimate): FoodVisionProvider => ({
    estimate: () => Promise.resolve(estimate),
  });

  it('should keep the photo and the estimate, and show the plate totals', async () => {
    const { service, rows } = world(seeing(plate));

    const result = await service.scan(7, photo, false);

    expect(result.scan_id).toBe(1);
    expect(result.items.map((i) => i.name)).toEqual([
      'Rice (cooked white)',
      'Dal tadka',
    ]);
    expect(result.totals.kcal).toBe(468);
    expect(result.totals.sodium_mg).toBe(542);
    const saved = rows.get(1)!;
    expect(await readdir(dir)).toEqual([saved.photoPath]);
  });

  it('should store nothing when the photo is not food', async () => {
    const { service, rows } = world(seeing(NOT_FOOD));

    const result = await service.scan(7, photo, false);

    expect(result.scan_id).toBeNull();
    expect(rows.get(1)).toMatchObject({ matched: false });
    expect(await readdir(dir)).toEqual([]);
  });

  it('should log only the items kept, summed from the stored estimate, with the photo', async () => {
    const { service, rows, logged } = world(seeing(plate));
    await service.scan(7, photo, false);
    const scannedPhoto = rows.get(1)!.photoPath;

    await service.confirm(7, 1, 'lunch', [1]);

    expect(logged[0]).toMatchObject({
      slot: 'lunch',
      name: 'Dal tadka',
      photoPath: scannedPhoto,
    });
    expect((logged[0].nutrition as { kcal: number }).kcal).toBe(216);
    // The photo is the entry's now.
    expect(rows.get(1)).toMatchObject({ foodLogId: 'log-1', photoPath: null });
  });

  it("should not let anyone confirm another person's scan, or one twice", async () => {
    const { service } = world(seeing(plate));
    await service.scan(7, photo, false);

    await expect(service.confirm(8, 1, 'lunch')).rejects.toMatchObject({
      status: 404,
    });
    await service.confirm(7, 1, 'lunch');
    await expect(service.confirm(7, 1, 'lunch')).rejects.toMatchObject({
      status: 404,
    });
  });

  it('should refuse a confirm that keeps nothing', async () => {
    const { service } = world(seeing(plate));
    await service.scan(7, photo, false);

    await expect(service.confirm(7, 1, 'lunch', [5])).rejects.toMatchObject({
      status: 422,
    });
  });

  it('should delete the photo at once when the user says no', async () => {
    const { service, rows } = world(seeing(plate));
    await service.scan(7, photo, false);

    await service.discard(7, 1);

    expect(await readdir(dir)).toEqual([]);
    expect(rows.get(1)).toMatchObject({ photoPath: null, estimate: null });
  });

  it('should say scanning is unavailable when no vision provider is configured', async () => {
    await expect(
      world(null).service.scan(7, photo, false),
    ).rejects.toMatchObject({
      status: 503,
    });
  });

  it('should refuse a file that is not a JPG or PNG', async () => {
    await expect(
      world(seeing(plate)).service.scan(
        7,
        { mimetype: 'application/pdf', buffer: Buffer.from('x') } as never,
        false,
      ),
    ).rejects.toMatchObject({ status: 400 });
  });

  it('should not count, or keep a photo of, a scan the vendor failed to answer', async () => {
    const { service, rows } = world({
      estimate: () => Promise.reject(new Error('network')),
    });

    await expect(service.scan(7, photo, false)).rejects.toMatchObject({
      status: 503,
    });
    expect(rows.size).toBe(0);
    expect(await readdir(dir)).toEqual([]);
  });
});

describe('ScanPolicyService status copy', () => {
  it('should carry the words to show when scanning is not allowed, and none when it is', async () => {
    const over = await policyService({ signedUpDaysAgo: 4 }).status(7, NOW);
    const ok = await policyService({ signedUpDaysAgo: 1 }).status(7, NOW);

    expect(over.user_message).toContain('Upgrade');
    expect(ok.user_message).toBeNull();
  });
});
