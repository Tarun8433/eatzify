import { LogsService } from '../src/logs/logs.service';

/// docs/21 §6: a diary entry carries its food's photograph and the credit it is shown with (D-83),
/// so Home's meal list can show what was eaten, not only its name.

const row = (over: Record<string, unknown>) => ({
  id: 'r1',
  slot: 'breakfast',
  customName: null,
  food: {
    name: 'Aloo gobhi',
    imageSlug: 'aloo-gobhi.jpg',
    imageAttribution: 'A. Cook / CC BY-SA 4.0',
  },
  quantityG: '150.0',
  measureLabel: 'katori',
  kcal: '161.0',
  proteinG: '3.0',
  carbG: '17.0',
  fatG: '9.0',
  fibreG: '4.0',
  source: 'manual',
  loggedAt: new Date('2026-09-19T03:00:00Z'),
  ...over,
});

const serviceWith = (rows: unknown[]) =>
  new LogsService(
    { find: () => Promise.resolve(rows) } as never,
    {} as never,
    { findOne: () => Promise.resolve(null) } as never,
    { find: () => Promise.resolve([]) } as never,
  );

describe('diary entries carry their photo (docs/21 §6)', () => {
  it('should give a food entry its photo path and credit', async () => {
    const day = await serviceWith([row({})]).day(7, '2026-09-19');

    expect(day.entries[0].image_url).toBe('/food-images/aloo-gobhi.jpg');
    expect(day.entries[0].image_attribution).toBe('A. Cook / CC BY-SA 4.0');
  });

  it('should give no photo to a custom entry or a food without one', async () => {
    const day = await serviceWith([
      row({ id: 'c', customName: 'Aunty ka halwa', food: null }),
      row({
        id: 'n',
        food: { name: 'Salt', imageSlug: null, imageAttribution: null },
      }),
    ]).day(7, '2026-09-19');

    expect(day.entries.map((e) => e.image_url)).toEqual([null, null]);
    expect(day.entries.map((e) => e.image_attribution)).toEqual([null, null]);
  });
});
