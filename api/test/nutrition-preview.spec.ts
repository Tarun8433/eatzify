import { LogsService } from '../src/logs/logs.service';
import { nutritionFor } from '../src/logs/nutrition-for';

/// D-238. The add sheet previews a portion before it is logged. Preview and log run the same
/// scaling, so what the sheet promised is exactly what the diary records.

const aloo = {
  id: '11111111-1111-4111-8111-111111111111',
  name: 'Aloo paratha',
  isVerified: true,
  kcal: '302.00',
  proteinG: '6.40',
  carbG: '40.10',
  fatG: '12.80',
  fibreG: '3.90',
  sodiumMg: '410.00',
  addedSugarG: '0.00',
  saturatedFatG: '4.20',
  measures: [{ label: 'piece', grams: '80.00' }],
};

const serviceWith = (food: unknown, saved: unknown[] = []) =>
  new LogsService(
    {
      save: (row: Record<string, unknown>) => {
        saved.push(row);
        return Promise.resolve({ ...row, id: 'log1', loggedAt: new Date() });
      },
    } as never,
    { findOne: () => Promise.resolve(food) } as never,
    {} as never,
    {} as never,
  );

describe('nutritionFor', () => {
  it('should scale every per-100 g value to the portion, one decimal', () => {
    const n = nutritionFor(aloo as never, 160);

    expect(n).toEqual({
      grams: 160,
      kcal: 483.2,
      protein_g: 10.2,
      carb_g: 64.2,
      fat_g: 20.5,
      fibre_g: 6.2,
      sodium_mg: 656,
      added_sugar_g: 0,
      saturated_fat_g: 6.7,
    });
  });
});

describe('LogsService.preview', () => {
  it('should price two pieces by the measure the food defines', async () => {
    const preview = await serviceWith(aloo).preview({
      food_id: aloo.id,
      measure: 'piece',
      measure_count: 2,
    });

    expect(preview.grams).toBe(160);
    expect(preview.sodium_mg).toBe(656);
  });

  it('should refuse a measure the food does not have rather than guess', async () => {
    await expect(
      serviceWith(aloo).preview({
        food_id: aloo.id,
        measure: 'katori',
        measure_count: 1,
      }),
    ).rejects.toMatchObject({ status: 422 });
  });

  it('should refuse an unverified food', async () => {
    await expect(
      serviceWith({ ...aloo, isVerified: false }).preview({
        food_id: aloo.id,
        quantity_g: 100,
      }),
    ).rejects.toMatchObject({ status: 422 });
  });

  it('should log exactly what it previewed', async () => {
    const saved: Record<string, unknown>[] = [];
    const service = serviceWith(aloo, saved);
    const portion = { food_id: aloo.id, measure: 'piece', measure_count: 2 };

    const preview = await service.preview(portion);
    await service.logFood(7, { ...portion, slot: 'breakfast' });

    expect(Number(saved[0].kcal)).toBe(preview.kcal);
    expect(Number(saved[0].proteinG)).toBe(preview.protein_g);
    expect(Number(saved[0].fibreG)).toBe(preview.fibre_g);
  });

  it('should record a confirmed scan as a photo entry, and default to manual', async () => {
    const saved: Record<string, unknown>[] = [];
    const service = serviceWith(aloo, saved);

    await service.logFood(7, {
      slot: 'lunch',
      food_id: aloo.id,
      quantity_g: 100,
      source: 'photo',
    });
    await service.logFood(7, {
      slot: 'lunch',
      food_id: aloo.id,
      quantity_g: 100,
    });

    expect(saved.map((r) => r.source)).toEqual(['photo', 'manual']);
  });
});
