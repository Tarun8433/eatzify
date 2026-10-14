import { HttpException, HttpStatus, Injectable } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { In, Repository } from 'typeorm';
import { FoodEntity } from '../foods/entities/food.entity';
import { ProfileEntity } from '../profile/entities/profile.entity';
import { LogsService, type LogEntryView } from '../logs/logs.service';
import type { NutritionView } from '../logs/nutrition-for';
import {
  RecipeEntity,
  RecipeIngredientEntity,
  type RecipeStatus,
} from './entities/recipe.entity';
import {
  allergens,
  perServing,
  recipeProblems,
  suitableFor,
  type RecipeDraftInput,
} from './recipe-rules';
import {
  RECIPE_FOOD_NOT_PUBLISHED,
  RECIPE_INVALID,
  RECIPE_NOT_FOUND,
  RECIPE_STEP_REFUSED,
  RECIPE_UNAVAILABLE,
} from './recipe-copy';

/// What the app and the admin panel are sent (snake_case at the boundary, api-conventions).
export type RecipeView = {
  id: string;
  name: string;
  name_hi: string | null;
  description: string;
  steps: string[];
  slots: string[];
  servings: number;
  status: RecipeStatus;
  suitable_for: string[];
  allergens: string[];
  per_serving: NutritionView;
  ingredients: {
    food_id: string;
    name: string;
    name_hi: string | null;
    grams: number;
  }[];
  /// False once any ingredient is no longer a published food — the recipe then leaves the app.
  available: boolean;
};

export type RecipeFilter = { suitableFor?: string; slot?: string };

const RELATIONS = { ingredients: { food: true } } as const;

/// D-263. Recipes are curated like foods and derive every figure from them.
@Injectable()
export class RecipesService {
  constructor(
    @InjectRepository(RecipeEntity)
    private readonly recipes: Repository<RecipeEntity>,
    @InjectRepository(FoodEntity)
    private readonly foods: Repository<FoodEntity>,
    private readonly logs: LogsService,
    @InjectRepository(ProfileEntity)
    private readonly profiles: Repository<ProfileEntity>,
  ) {}

  /// The caller's own food preference (docs/03 §2) — the list's default filter, so a vegetarian is
  /// never shown chicken because the app forgot to ask. Null before onboarding: everything shows.
  async preferenceOf(userId: number): Promise<string | null> {
    const profile = await this.profiles.findOne({
      where: { userId },
      select: { userId: true, foodPreference: true },
    });
    return profile?.foodPreference ?? null;
  }

  /// The app's list: published, every ingredient still published, narrowed to one food preference
  /// and one meal when asked.
  /// ponytail: filtered in memory — recipes are a curated list of tens, not a user-growable one
  /// (api-conventions' cursor rule). Move the filter into SQL if it reaches the thousands.
  async listPublished(filter: RecipeFilter): Promise<RecipeView[]> {
    const rows = await this.recipes.find({
      where: { status: 'published' },
      relations: RELATIONS,
      order: { name: 'ASC' },
    });
    return rows
      .map((r) => this.toView(r))
      .filter(
        (v) =>
          v.available &&
          (!filter.suitableFor ||
            v.suitable_for.includes(filter.suitableFor)) &&
          (!filter.slot || v.slots.includes(filter.slot)),
      );
  }

  async getPublished(id: string): Promise<RecipeView> {
    const view = this.toView(await this.mustFind(id));
    if (view.status !== 'published' || !view.available) {
      throw this.refuse(
        HttpStatus.NOT_FOUND,
        'RECIPE_NOT_FOUND',
        RECIPE_NOT_FOUND,
      );
    }
    return view;
  }

  /// Logs [servings] of a published recipe: one diary entry per ingredient, through the same
  /// `logFood` every food goes through, so the diary day and the copied nutrition follow the
  /// diary's own rules (rule 8) and a recipe's entries can be edited one by one like any other.
  /// ponytail: entries are written one at a time; a failure part-way leaves the earlier ones
  /// logged, which the user sees and can delete. Wrap in one transaction if that ever matters.
  async log(
    userId: number,
    id: string,
    slot: string,
    servings: number,
  ): Promise<LogEntryView[]> {
    const recipe = await this.mustFind(id);
    const view = this.toView(recipe);
    if (view.status !== 'published' || !view.available) {
      throw this.refuse(
        HttpStatus.CONFLICT,
        'RECIPE_UNAVAILABLE',
        RECIPE_UNAVAILABLE,
      );
    }

    const entries: LogEntryView[] = [];
    for (const ingredient of sorted(recipe.ingredients)) {
      const grams = (Number(ingredient.grams) * servings) / recipe.servings;
      entries.push(
        await this.logs.logFood(userId, {
          slot,
          food_id: ingredient.foodId,
          quantity_g: Math.round(grams * 10) / 10,
        }),
      );
    }
    return entries;
  }

  // --- admin ---

  async byStatus(status: RecipeStatus): Promise<RecipeView[]> {
    const rows = await this.recipes.find({
      where: { status },
      relations: RELATIONS,
      order: { updatedAt: 'DESC' },
    });
    return rows.map((r) => this.toView(r));
  }

  /// A DRAFT whatever the body says. Ingredients must already be published foods: a draft food's
  /// numbers have not been checked, and a recipe would carry them past the review.
  async createDraft(
    input: RecipeDraftInput & { nameHi: string | null; description: string },
    byUserId: number,
  ): Promise<RecipeView> {
    const problems = recipeProblems(input);
    const foodIds = input.ingredients.map((i) => i.foodId);
    const found = foodIds.length
      ? await this.foods.find({ where: { id: In(foodIds) } })
      : [];
    const unpublished = foodIds.filter(
      (fid) => !found.find((f) => f.id === fid)?.isVerified,
    );
    if (unpublished.length > 0)
      problems.push(`ingredients: ${RECIPE_FOOD_NOT_PUBLISHED}`);
    if (problems.length > 0) throw this.invalid(problems);

    const saved = await this.recipes.save(
      this.recipes.create({
        name: input.name.trim(),
        nameHi: input.nameHi?.trim() || null,
        description: input.description.trim(),
        steps: input.steps.map((s) => s.trim()).filter((s) => s !== ''),
        slots: input.slots,
        servings: input.servings,
        status: 'draft',
        createdByUserId: byUserId,
        ingredients: input.ingredients.map((i, position) =>
          this.recipes.manager.create(RecipeIngredientEntity, {
            foodId: i.foodId,
            grams: i.grams.toFixed(1),
            position,
          }),
        ),
      }),
    );
    return this.toView(await this.mustFind(saved.id));
  }

  async review(id: string, byUserId: number, now: Date): Promise<RecipeView> {
    const recipe = await this.mustFind(id);
    if (recipe.status !== 'draft' && recipe.status !== 'retired') {
      throw this.refuseStep();
    }
    recipe.status = 'reviewed';
    recipe.reviewedByUserId = byUserId;
    recipe.reviewedAt = now;
    return this.saveAndView(recipe);
  }

  /// Only from `reviewed`, and only while every ingredient is still a published food.
  async publish(id: string, byUserId: number, now: Date): Promise<RecipeView> {
    const recipe = await this.mustFind(id);
    if (recipe.status !== 'reviewed') throw this.refuseStep();
    if (!this.toView(recipe).available) {
      throw this.invalid([`ingredients: ${RECIPE_FOOD_NOT_PUBLISHED}`]);
    }
    recipe.status = 'published';
    recipe.publishedByUserId = byUserId;
    recipe.publishedAt = now;
    return this.saveAndView(recipe);
  }

  /// Out of the app, not deleted — its entries are already copied into diaries.
  async retire(id: string, byUserId: number, now: Date): Promise<RecipeView> {
    const recipe = await this.mustFind(id);
    recipe.status = 'retired';
    recipe.reviewedByUserId = byUserId;
    recipe.reviewedAt = now;
    return this.saveAndView(recipe);
  }

  // --- helpers ---

  toView(recipe: RecipeEntity): RecipeView {
    const ingredients = sorted(recipe.ingredients);
    const parts = ingredients.map((i) => ({
      food: i.food,
      grams: Number(i.grams),
    }));
    return {
      id: recipe.id,
      name: recipe.name,
      name_hi: recipe.nameHi,
      description: recipe.description,
      steps: recipe.steps,
      slots: recipe.slots,
      servings: recipe.servings,
      status: recipe.status,
      suitable_for: suitableFor(parts),
      allergens: allergens(parts),
      per_serving: perServing(parts, recipe.servings),
      ingredients: ingredients.map((i) => ({
        food_id: i.foodId,
        name: i.food.name,
        name_hi: i.food.nameHi,
        grams: Number(i.grams),
      })),
      available:
        ingredients.length > 0 && ingredients.every((i) => i.food.isVerified),
    };
  }

  private async saveAndView(recipe: RecipeEntity): Promise<RecipeView> {
    // Saved without the relation so the cascade never rewrites the ingredient rows.
    const { ingredients, ...row } = recipe;
    await this.recipes.save(row);
    return this.toView({ ...recipe, ingredients } as RecipeEntity);
  }

  private async mustFind(id: string): Promise<RecipeEntity> {
    const recipe = await this.recipes.findOne({
      where: { id },
      relations: RELATIONS,
    });
    if (!recipe) {
      throw this.refuse(
        HttpStatus.NOT_FOUND,
        'RECIPE_NOT_FOUND',
        RECIPE_NOT_FOUND,
      );
    }
    return recipe;
  }

  private invalid(problems: string[]): HttpException {
    return new HttpException(
      {
        status: HttpStatus.UNPROCESSABLE_ENTITY,
        error: {
          code: 'RECIPE_INVALID',
          user_message: RECIPE_INVALID,
          details: { errors: problems.map(splitProblem) },
        },
      },
      HttpStatus.UNPROCESSABLE_ENTITY,
    );
  }

  private refuseStep(): HttpException {
    return this.refuse(
      HttpStatus.CONFLICT,
      'RECIPE_STEP_REFUSED',
      RECIPE_STEP_REFUSED,
    );
  }

  private refuse(
    status: HttpStatus,
    code: string,
    userMessage: string,
  ): HttpException {
    return new HttpException(
      { status, error: { code, user_message: userMessage } },
      status,
    );
  }
}

const sorted = (ingredients: RecipeIngredientEntity[] = []) =>
  [...ingredients].sort((a, b) => a.position - b.position);

/// `field: message` → the `{ field, message }` shape the food importer's errors use, so the admin
/// panel shows both the same way.
function splitProblem(problem: string): { field: string; message: string } {
  const at = problem.indexOf(': ');
  return at < 0
    ? { field: 'recipe', message: problem }
    : { field: problem.slice(0, at), message: problem.slice(at + 2) };
}
