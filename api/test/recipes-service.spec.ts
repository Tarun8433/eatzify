import { RecipesService } from '../src/recipes/recipes.service';
import type { RecipeEntity } from '../src/recipes/entities/recipe.entity';

type Food = {
  id: string;
  name: string;
  nameHi: null;
  isVerified: boolean;
  kcal: string;
  proteinG: string;
  carbG: string;
  fatG: string;
  fibreG: string;
  sodiumMg: string;
  addedSugarG: string;
  saturatedFatG: string;
  suitableFor: string[];
  allergens: string[];
};

const food = (id: string, over: Partial<Food> = {}): Food => ({
  id,
  name: id,
  nameHi: null,
  isVerified: true,
  kcal: '100',
  proteinG: '10',
  carbG: '10',
  fatG: '2',
  fibreG: '0',
  sodiumMg: '0',
  addedSugarG: '0',
  saturatedFatG: '0',
  suitableFor: ['veg', 'vegan', 'eggetarian', 'non_veg'],
  allergens: [],
  ...over,
});

/// D-263 through RecipesService, with the two repositories and the logger faked in memory.
function harness(foods: Food[]) {
  const recipes: RecipeEntity[] = [];
  const logged: { slot: string; food_id: string; quantity_g: number }[] = [];
  const withFoods = (r: RecipeEntity): RecipeEntity =>
    ({
      ...r,
      ingredients: r.ingredients.map((i) => ({
        ...i,
        food: foods.find((f) => f.id === i.foodId)!,
      })),
    }) as RecipeEntity;

  const repo = {
    find: ({ where }: { where: { status: string } }) =>
      Promise.resolve(
        recipes.filter((r) => r.status === where.status).map(withFoods),
      ),
    findOne: ({ where }: { where: { id: string } }) => {
      const r = recipes.find((x) => x.id === where.id);
      return Promise.resolve(r ? withFoods(r) : null);
    },
    create: (d: Partial<RecipeEntity>) => d,
    save: (d: Partial<RecipeEntity>) => {
      const existing = recipes.find((r) => r.id === d.id);
      if (existing) {
        Object.assign(existing, d);
        return Promise.resolve(existing);
      }
      const row = { ...d, id: `r${recipes.length + 1}` } as RecipeEntity;
      recipes.push(row);
      return Promise.resolve(row);
    },
    manager: { create: (_: unknown, d: object) => d },
  };
  const foodRepo = {
    find: () => Promise.resolve(foods),
  };
  const logs = {
    logFood: (_user: number, dto: (typeof logged)[number]) => {
      logged.push(dto);
      return Promise.resolve(dto);
    },
  };
  const service = new RecipesService(
    repo as never,
    foodRepo as never,
    logs as never,
    { findOne: () => Promise.resolve(null) } as never,
  );
  return { service, recipes, logged, foods };
}

const draft = {
  name: 'Moong chilla',
  nameHi: null,
  description: '',
  steps: ['Mix', ''],
  slots: ['breakfast'],
  servings: 2,
  ingredients: [
    { foodId: 'dal', grams: 100 },
    { foodId: 'oil', grams: 10 },
  ],
};

async function published(h: ReturnType<typeof harness>) {
  const view = await h.service.createDraft(draft, 7);
  await h.service.review(view.id, 7, new Date());
  await h.service.publish(view.id, 8, new Date());
  return view.id;
}

describe('RecipesService', () => {
  it('should save a draft with derived per-serving nutrition and drop blank steps', async () => {
    const h = harness([food('dal'), food('oil', { kcal: '900', fatG: '100' })]);
    const view = await h.service.createDraft(draft, 7);

    expect(view).toMatchObject({
      status: 'draft',
      steps: ['Mix'],
      // (100 + 90) kcal over 2 servings.
      per_serving: { kcal: 95 },
    });
  });

  it('should refuse a draft whose ingredient is not a published food', async () => {
    const h = harness([food('dal'), food('oil', { isVerified: false })]);
    await expect(h.service.createDraft(draft, 7)).rejects.toMatchObject({
      status: 422,
      response: { error: { code: 'RECIPE_INVALID' } },
    });
    expect(h.recipes).toHaveLength(0);
  });

  it('should refuse to publish a draft that was never reviewed', async () => {
    const h = harness([food('dal'), food('oil')]);
    const view = await h.service.createDraft(draft, 7);
    await expect(
      h.service.publish(view.id, 8, new Date()),
    ).rejects.toMatchObject({
      response: { error: { code: 'RECIPE_STEP_REFUSED' } },
    });
  });

  it('should log one entry per ingredient scaled to the servings eaten', async () => {
    const h = harness([food('dal'), food('oil')]);
    const id = await published(h);

    // The recipe makes 2 servings; 1 serving is half of every ingredient.
    await h.service.log(1, id, 'lunch', 1);
    expect(h.logged).toEqual([
      { slot: 'lunch', food_id: 'dal', quantity_g: 50 },
      { slot: 'lunch', food_id: 'oil', quantity_g: 5 },
    ]);
  });

  it('should list only recipes every ingredient of which is still published and suits the filter', async () => {
    const h = harness([
      food('dal'),
      food('oil', { suitableFor: ['veg', 'non_veg'] }),
    ]);
    await published(h);

    expect(await h.service.listPublished({ suitableFor: 'veg' })).toHaveLength(
      1,
    );
    expect(
      await h.service.listPublished({ suitableFor: 'vegan' }),
    ).toHaveLength(0);
    expect(await h.service.listPublished({ slot: 'dinner' })).toHaveLength(0);

    // A food retired after publishing takes the recipe out of the app.
    h.foods[1].isVerified = false;
    expect(await h.service.listPublished({})).toHaveLength(0);
    await expect(h.service.log(1, 'r1', 'lunch', 1)).rejects.toMatchObject({
      response: { error: { code: 'RECIPE_UNAVAILABLE' } },
    });
  });
});
