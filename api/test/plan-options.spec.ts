import { PlanOptionsService } from '../src/plans/plan-options.service';
import type { Constraints } from '@eatzify/diet-engine';

const food = (over: Record<string, unknown> = {}) =>
  ({
    id: 'f1',
    name: 'Dal tadka',
    nameHi: null,
    kcal: 120,
    proteinG: 8,
    tags: [],
    suitableFor: ['veg', 'non_veg'],
    allergens: [],
    costTier: 'low',
    imageSlug: null,
    imageAttribution: null,
    measures: [{ label: 'katori', grams: 150, isDefault: true }],
    ...over,
  }) as never;

const serviceWith = (rows: unknown[]) =>
  new PlanOptionsService({ find: () => Promise.resolve(rows) } as never);

/// Options for one slot. Every test below is about the filtering, not about which slot it ran for,
/// so they all ask for lunch and read that key.
const forLunch = async (
  service: PlanOptionsService,
  profileRow: Parameters<PlanOptionsService['forUser']>[0],
  health: Parameters<PlanOptionsService['forUser']>[1],
  rules: Parameters<PlanOptionsService['forUser']>[2],
) => (await service.forUser(profileRow, health, rules, ['lunch']))['lunch'];

const profile = (over: Record<string, unknown> = {}) =>
  ({ foodPreference: 'veg', budgetTier: 'medium', ...over }) as never;

const constraints = (over: Partial<Constraints> = {}) =>
  ({ excludeTags: [], preferTags: [], ...over }) as Constraints;

describe('the foods a user may choose from (D-82)', () => {
  it('keeps what suits their declared preference', async () => {
    const service = serviceWith([
      food({ id: 'veg', suitableFor: ['veg'] }),
      food({ id: 'meat', suitableFor: ['non_veg'] }),
    ]);

    const out = await forLunch(service, profile(), null, constraints());
    expect(out.map((o) => o.id)).toEqual(['veg']);
  });

  it('drops anything they are allergic to — the one filter that never bends', async () => {
    const service = serviceWith([
      food({ id: 'safe' }),
      food({ id: 'milky', allergens: ['milk'] }),
    ]);

    const out = await forLunch(
      service,
      profile(),
      { allergies: ['milk'] } as never,
      constraints(),
    );
    expect(out.map((o) => o.id)).toEqual(['safe']);
  });

  it('drops what their budget cannot reach, and keeps what it can', async () => {
    const rows = [
      food({ id: 'cheap', costTier: 'low' }),
      food({ id: 'mid', costTier: 'medium' }),
      food({ id: 'dear', costTier: 'premium' }),
    ];

    const onMedium = await forLunch(
      serviceWith(rows),
      profile(),
      null,
      constraints(),
    );
    expect(new Set(onMedium.map((o) => o.id))).toEqual(
      new Set(['cheap', 'mid']),
    );

    // A premium budget can still buy cheap food — the tier is a ceiling, not a bracket.
    const onPremium = await forLunch(
      serviceWith(rows),
      profile({ budgetTier: 'premium' }),
      null,
      constraints(),
    );
    // A set: these fixtures share a name, so their relative order carries no meaning.
    expect(new Set(onPremium.map((o) => o.id))).toEqual(
      new Set(['cheap', 'mid', 'dear']),
    );
  });

  it("honours the rule pack's exclude tags rather than a list written here", async () => {
    const service = serviceWith([
      food({ id: 'lowgi', tags: ['gi:low'] }),
      food({ id: 'highgi', tags: ['gi:high'] }),
    ]);

    const out = await forLunch(
      service,
      profile(),
      null,
      constraints({ excludeTags: ['gi:high'] }),
    );
    expect(out.map((o) => o.id)).toEqual(['lowgi']);
  });

  it('orders preferred foods first without hiding the rest', async () => {
    const service = serviceWith([
      food({ id: 'plain', name: 'Aaa plain', tags: [] }),
      food({ id: 'good', name: 'Zzz preferred', tags: ['attr:high_protein'] }),
    ]);

    const out = await forLunch(
      service,
      profile(),
      null,
      constraints({ preferTags: ['attr:high_protein'] }),
    );
    // Preferred first despite sorting last by name, and nothing dropped for not being preferred.
    expect(out.map((o) => o.id)).toEqual(['good', 'plain']);
  });

  it('reports the household measure and its energy, so the list needs no arithmetic', async () => {
    const out = await forLunch(
      serviceWith([food()]),
      profile(),
      null,
      constraints(),
    );
    expect(out[0].default_measure).toEqual({ label: 'katori', grams: 150 });
    expect(out[0].kcal_per_measure).toBe(180);
  });

  it('carries the photograph and the credit it is served under', async () => {
    const out = await forLunch(
      serviceWith([
        food({
          imageSlug: 'dal-tadka.jpg',
          imageAttribution: 'Someone / Wikimedia Commons / CC BY-SA 4.0',
        }),
      ]),
      profile(),
      null,
      constraints(),
    );

    expect(out[0].image_url).toBe('/food-images/dal-tadka.jpg');
    // CC BY and CC BY-SA require the author to be named wherever the image appears, so the credit
    // travels with the URL and is never separable from it (D-83).
    expect(out[0].image_attribution).toBe(
      'Someone / Wikimedia Commons / CC BY-SA 4.0',
    );
  });

  it('a food with no photograph reports null, not a broken path', async () => {
    const out = await forLunch(
      serviceWith([food({ imageSlug: null })]),
      profile(),
      null,
      constraints(),
    );
    expect(out[0].image_url).toBeNull();
  });

  it('a food with no measure still lists, with grams as the fallback', async () => {
    const out = await forLunch(
      serviceWith([food({ measures: [] })]),
      profile(),
      null,
      constraints(),
    );
    expect(out[0].default_measure).toBeNull();
    expect(out[0].kcal_per_measure).toBeNull();
  });

  it('with no constraints at all it still filters on the profile', async () => {
    // A user whose plan is blocked can still browse: null constraints must not mean "anything".
    const out = await forLunch(
      serviceWith([
        food({ id: 'veg', suitableFor: ['veg'] }),
        food({ id: 'meat', suitableFor: ['non_veg'] }),
      ]),
      profile(),
      null,
      null,
    );

    expect(out.map((o) => o.id)).toEqual(['veg']);
  });

  describe('each slot gets its own list (D-85)', () => {
    const rows = [
      food({ id: 'poha', name: 'Poha', tags: ['meal:breakfast'] }),
      food({ id: 'dal', name: 'Dal', tags: ['meal:lunch', 'meal:dinner'] }),
      food({ id: 'apple', name: 'Apple', tags: [] }),
    ];

    it('offers a food only for the meals it is tagged for', async () => {
      const out = await serviceWith(rows).forUser(
        profile(),
        null,
        constraints(),
        ['breakfast', 'lunch'],
      );

      expect(out.breakfast.map((o) => o.id)).toEqual(['apple', 'poha']);
      expect(out.lunch.map((o) => o.id)).toEqual(['apple', 'dal']);
    });

    it('an untagged food belongs anywhere — an apple is not wrong for breakfast', async () => {
      const out = await serviceWith(rows).forUser(
        profile(),
        null,
        constraints(),
        ['breakfast', 'dinner'],
      );

      expect(out.breakfast.map((o) => o.id)).toContain('apple');
      expect(out.dinner.map((o) => o.id)).toContain('apple');
    });

    it('the small slots all draw from snacks', async () => {
      const snacks = [food({ id: 'chana', tags: ['meal:snack'] })];
      const out = await serviceWith(snacks).forUser(
        profile(),
        null,
        constraints(),
        ['mid_morning', 'evening', 'bedtime'],
      );

      for (const slot of ['mid_morning', 'evening', 'bedtime']) {
        expect(out[slot].map((o) => o.id)).toEqual(['chana']);
      }
    });

    it('breakfast and dinner are not the same list any more', async () => {
      // The report: aloo gobhi suggested for breakfast, lunch, snack AND dinner. A plan that
      // suggests the same twelve foods four times is not suggesting anything.
      const out = await serviceWith(rows).forUser(
        profile(),
        null,
        constraints(),
        ['breakfast', 'dinner'],
      );

      expect(out.breakfast.map((o) => o.id)).not.toEqual(
        out.dinner.map((o) => o.id),
      );
    });

    it('returns nothing for a slot the plan does not have', async () => {
      const out = await serviceWith(rows).forUser(
        profile(),
        null,
        constraints(),
        ['lunch'],
      );
      expect(Object.keys(out)).toEqual(['lunch']);
    });
  });
});
