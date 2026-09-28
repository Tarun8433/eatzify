import { mkdtemp, readdir, rm, utimes } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { parseEstimate, sumItems } from '../src/foods/scan/plate-estimate';
import { MealPhotoSweep } from '../src/foods/scan/meal-photo.sweep';
import {
  saveMealPhoto,
  signedPhotoPath,
  verifyPhotoLink,
} from '../src/logs/meal-photo';

/// D-240. A model's plate estimate is checked before anything is stored; the user's photo is served
/// only through a signed, expiring link; and the sweep deletes what nothing should still hold.

const item = {
  name: 'Rice',
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
const answer = (over: Record<string, unknown>) =>
  JSON.stringify({
    is_food: true,
    dish_name: 'Rice',
    confidence: 0.7,
    items: [item],
    ...over,
  });

describe('parseEstimate', () => {
  it('should accept a sane answer', () => {
    expect(parseEstimate(answer({}))?.items[0].kcal).toBe(252);
  });

  it('should refuse an absurd number rather than log it', () => {
    expect(
      parseEstimate(answer({ items: [{ ...item, kcal: 90000 }] })),
    ).toBeNull();
    expect(
      parseEstimate(answer({ items: [{ ...item, grams: -5 }] })),
    ).toBeNull();
  });

  it('should refuse text that is not the schema', () => {
    expect(parseEstimate('Looks like rice!')).toBeNull();
    expect(parseEstimate('{"dish": "rice"}')).toBeNull();
    expect(parseEstimate(null)).toBeNull();
  });

  it('should name the plate from its items when the model gave no name', () => {
    expect(
      parseEstimate(
        answer({ dish_name: '', items: [item, { ...item, name: 'Dal' }] }),
      )?.dishName,
    ).toBe('Rice + Dal');
  });
});

describe('sumItems', () => {
  it('should add every nutrient across the items, to one decimal', () => {
    const total = sumItems([item, { ...item, fibre_g: 0.44 }]);

    expect(total.kcal).toBe(504);
    expect(total.fibre_g).toBe(1.2);
    expect(total.grams).toBe(400);
  });
});

describe('signed photo links', () => {
  beforeAll(() => (process.env.AUTH_JWT_SECRET = 'test-secret'));

  const parts = (path: string) => {
    const url = new URL(path, 'http://api.test');
    return [url.searchParams.get('exp')!, url.searchParams.get('sig')!];
  };

  it('should verify a link for the entry it was signed for, until it expires', () => {
    const now = Date.now();
    const [exp, sig] = parts(signedPhotoPath('log-a', now));

    expect(verifyPhotoLink('log-a', exp, sig, now)).toBe(true);
    // Another entry's id with this signature is refused…
    expect(verifyPhotoLink('log-b', exp, sig, now)).toBe(false);
    // …and so is the right link, two hours later.
    expect(verifyPhotoLink('log-a', exp, sig, now + 2 * 3600 * 1000)).toBe(
      false,
    );
  });

  it('should refuse a link with its expiry edited', () => {
    const now = Date.now();
    const [exp, sig] = parts(signedPhotoPath('log-a', now));

    expect(
      verifyPhotoLink('log-a', String(Number(exp) + 86400), sig, now),
    ).toBe(false);
  });
});

describe('MealPhotoSweep', () => {
  const DAY = 24 * 60 * 60 * 1000;
  let dir: string;

  beforeEach(async () => {
    dir = await mkdtemp(join(tmpdir(), 'meal-photos-'));
    process.env.MEAL_PHOTO_DIR = dir;
  });
  afterEach(async () => {
    delete process.env.MEAL_PHOTO_DIR;
    await rm(dir, { recursive: true, force: true });
  });

  it('should delete unconfirmed, expired and orphaned photos, and keep the rest', async () => {
    const now = new Date();
    const aged = async (name: string, days: number) => {
      const t = new Date(now.getTime() - days * DAY);
      await utimes(join(dir, name), t, t);
    };
    const pending = await saveMealPhoto(Buffer.from('a'), 'jpg');
    const expired = await saveMealPhoto(Buffer.from('b'), 'jpg');
    const kept = await saveMealPhoto(Buffer.from('c'), 'jpg');
    const orphan = await saveMealPhoto(Buffer.from('d'), 'jpg');
    const fresh = await saveMealPhoto(Buffer.from('e'), 'jpg');
    for (const name of [pending, expired, kept, orphan]) await aged(name, 2);

    // Queries are answered by what each pass asks for: stale scans, expired entries, then every
    // row still pointing at a photo.
    const updated: unknown[] = [];
    const scans = {
      find: jest
        .fn()
        .mockResolvedValueOnce([{ id: 1, photoPath: pending }])
        .mockResolvedValueOnce([]),
      update: (id: unknown, patch: unknown) => updated.push(patch),
    };
    const logs = {
      find: jest
        .fn()
        .mockResolvedValueOnce([{ id: 'x', photoPath: expired }])
        .mockResolvedValueOnce([{ id: 'y', photoPath: kept }]),
      update: (id: unknown, patch: unknown) => updated.push(patch),
    };

    const removed = await new MealPhotoSweep(scans as never, logs as never).run(
      now,
    );

    expect(removed).toBe(3);
    expect((await readdir(dir)).sort()).toEqual([fresh, kept].sort());
    expect(updated).toEqual([
      { photoPath: null, estimate: null },
      { photoPath: null },
    ]);
  });
});
