import { Injectable } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import type { Constraints } from '@eatzify/diet-engine';
import { FoodEntity } from '../foods/entities/food.entity';
import { ProfileEntity } from '../profile/entities/profile.entity';
import { HealthProfileEntity } from '../profile/entities/health-profile.entity';

export type FoodOptionView = {
  id: string;
  name: string;
  name_hi: string | null;
  kcal_per_100g: number;
  protein_g_per_100g: number;
  /// The measure a person would say out loud — "1 katori". Null when the food has none recorded.
  default_measure: { label: string; grams: number } | null;
  /// Energy for one of that measure, so the list can be read without arithmetic. Null with no
  /// measure: grams are the fallback and the log sheet asks for them.
  kcal_per_measure: number | null;
  /// Relative to the API root. Null when the food has no photograph — the app draws a placeholder
  /// rather than a broken image.
  image_url: string | null;
  /// The credit the photograph is served under. CC BY and CC BY-SA REQUIRE it wherever the image
  /// is shown, so it travels with the URL and is never optional to render (D-83).
  image_attribution: string | null;
};

/// Foods a user may pick from for a meal slot (D-82).
///
/// **This is not the engine's candidate pool.** docs/04 steps 11, 13 and 14 — pool, greedy fill and
/// alternates — build a plan: they choose foods AND portions to hit a slot's targets. This does
/// neither. It filters the food table by what we already know about the user and hands the list to
/// them; they pick, and they say how much. Nothing here decides what anyone eats.
///
/// Every filter below is a fact already recorded, not a judgement made here:
/// * `suitableFor` against their declared food preference
/// * `allergens` against their declared allergies — a hard exclusion, never a preference
/// * `costTier` against their budget tier
/// * `tags` against the rule pack's own `exclude_tags` for their conditions, via the engine
@Injectable()
export class PlanOptionsService {
  constructor(
    @InjectRepository(FoodEntity)
    private readonly foods: Repository<FoodEntity>,
  ) {}

  /// Which `meal:*` tag a plan slot draws from. The rule pack splits a day into seven slots; the
  /// food table only distinguishes four kinds of eating, so the small ones all draw from snacks.
  private static readonly SLOT_TAG: Record<string, string> = {
    breakfast: 'meal:breakfast',
    lunch: 'meal:lunch',
    dinner: 'meal:dinner',
    snack: 'meal:snack',
    mid_morning: 'meal:snack',
    evening: 'meal:snack',
    bedtime: 'meal:snack',
  };

  /// Cost tiers a budget can reach: a premium budget can still buy cheap food.
  private static readonly AFFORDABLE: Record<string, string[]> = {
    low: ['low'],
    medium: ['low', 'medium'],
    premium: ['low', 'medium', 'premium'],
  };

  /// Options for each of [slots], keyed by slot (D-85).
  ///
  /// Per slot, because one list under every meal was the same twelve foods four times over — a
  /// plan that suggests aloo gobhi for breakfast, lunch and dinner is not suggesting anything.
  async forUser(
    profile: ProfileEntity,
    health: HealthProfileEntity | null,
    constraints: Constraints | null,
    slots: readonly string[],
    limit = 12,
  ): Promise<Record<string, FoodOptionView[]>> {
    const affordable = PlanOptionsService.AFFORDABLE[profile.budgetTier] ?? [
      'low',
      'medium',
    ];

    const rows = await this.foods.find({
      where: { isVerified: true },
      relations: { measures: true },
      order: { name: 'ASC' },
    });

    const allergies = new Set(health?.allergies ?? []);
    const excluded = new Set(constraints?.excludeTags ?? []);
    const preferred = new Set(constraints?.preferTags ?? []);

    const eligible = rows.filter((food) => {
      if (!food.suitableFor.includes(profile.foodPreference)) return false;
      // An allergen is a hard exclusion. It is the one filter here that must never be relaxed to
      // fill a short list.
      if (food.allergens.some((a) => allergies.has(a))) return false;
      if (!affordable.includes(food.costTier)) return false;
      if (food.tags.some((t) => excluded.has(t))) return false;
      return true;
    });

    // Foods the rule pack prefers for this user's conditions come first. Ordering only — nothing is
    // hidden for failing to be preferred, and the rest of the list follows in name order.
    const ranked = [...eligible].sort((a, b) => {
      const score = (f: FoodEntity) =>
        f.tags.some((t) => preferred.has(t)) ? 0 : 1;
      return score(a) - score(b) || a.name.localeCompare(b.name);
    });

    const bySlot: Record<string, FoodOptionView[]> = {};
    for (const slot of slots) {
      const tag = PlanOptionsService.SLOT_TAG[slot];
      const forSlot = ranked.filter((food) => {
        const meals = food.tags.filter((t) => t.startsWith('meal:'));
        // A food with no meal tag at all is not "wrong for breakfast" — it is untagged, and an
        // apple belongs anywhere. Only a food tagged for OTHER meals is excluded.
        return meals.length === 0 || (tag !== undefined && meals.includes(tag));
      });
      bySlot[slot] = forSlot.slice(0, limit).map((food) => this.toView(food));
    }

    return bySlot;
  }

  private toView(food: FoodEntity): FoodOptionView {
    const measure =
      food.measures?.find((m) => m.isDefault) ?? food.measures?.[0] ?? null;
    const grams = measure === null ? null : Number(measure.grams);

    return {
      id: food.id,
      name: food.name,
      name_hi: food.nameHi ?? null,
      kcal_per_100g: Number(food.kcal),
      protein_g_per_100g: Number(food.proteinG),
      default_measure:
        measure === null || grams === null
          ? null
          : { label: measure.label, grams },
      kcal_per_measure:
        grams === null ? null : Math.round((Number(food.kcal) * grams) / 100),
      image_url:
        food.imageSlug === null ? null : `/food-images/${food.imageSlug}`,
      image_attribution: food.imageAttribution ?? null,
    };
  }
}
