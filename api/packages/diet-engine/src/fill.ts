/**
 * docs/04 §2 step 13 — fill each meal from the candidate pool.
 *
 * **This is a bounded beam search, not the greedy of docs/04 §7, and that is deliberate (D-231).**
 * §7 specifies "greedy by protein density, then a repair pass" because it is simple; seven
 * iterations of exactly that (D-167) proved it insufficient. Greedy-plus-repair is being asked to
 * satisfy energy, protein, fat, sodium and added sugar at once, from a 250-item set, in half-serving
 * steps — and every fix for one constraint broke the next. A plan that misses the day's energy by
 * 48 % is not a plan, whatever the specification says the method should be.
 *
 * The search keeps the same guarantees the greedy had:
 *
 * - **Bounded.** Beam width × candidates × depth, all constants below. No loop can run long.
 * - **Pure and deterministic.** The pool arrives ordered by the caller, every tie breaks on food id,
 *   and nothing here reads a clock or a random source. Same pool in, same plan out, forever.
 * - **Household increments only.** 1.5 katori is real; 137 g is not.
 * - **A meal with nothing admissible comes back EMPTY**, never padded with something the pool said
 *   no to. An empty slot is visible and arguable; a wrong one is neither.
 */

import type { EngineFood, EngineMeasure } from './foods';
import type { RulePack } from './pack';
import type { Constraints, MealTarget } from './types';

export interface MealItem {
  readonly foodId: string;
  readonly name: string;
  /** The serving the plan speaks in — "katori", "roti". */
  readonly measureLabel: string;
  /** How many of them, on the pack's increment. 1.5 katori, never 137 g. */
  readonly quantity: number;
  readonly grams: number;
  readonly kcal: number;
  readonly proteinG: number;
  readonly fatG: number;
  readonly carbG: number;
  readonly fibreG: number;
  readonly sodiumMg: number;
}

export interface Meal {
  readonly slot: string;
  readonly items: readonly MealItem[];
  readonly kcal: number;
  readonly proteinG: number;
  readonly fatG: number;
  readonly carbG: number;
  readonly fibreG: number;
  readonly sodiumMg: number;
  /** Signed kcal distance from this meal's target. Zero means the fill landed exactly. */
  readonly residualKcal: number;
  /** True when the search could not reach the kcal tolerance (docs/04 §7). */
  readonly approximated: boolean;
}

/** How many states survive each level of the search. */
const BEAM_WIDTH = 8;

/** The most increments one meal may be built from — the search's depth. */
const MAX_INCREMENTS = 24;

/** Nobody is served ten katori of one thing. A ceiling per food, in servings. Shared with
 * step 14: an alternate may not suggest a portion the fill itself would refuse. */
export const MAX_SERVINGS_PER_FOOD = 6;

/** Levels without an improvement before the search accepts it has converged. */
const PATIENCE = 3;

/**
 * What the search is trying to be good at, in one number.
 *
 * Energy is weighted hardest because it is what docs/04 §8 asserts and what a person notices.
 * Protein is next: it is the point of the plan. Fat, sodium and added sugar are ceilings — only
 * being OVER them costs anything, so they steer without blocking, which is what stops the search
 * refusing to fill a meal at all.
 */
const WEIGHT = {
  kcal: 12,
  protein: 6,
  fat: 2,
  sodium: 3,
  addedSugar: 3,
  /**
   * A small price per distinct food. Without it the search happily adds a cup of green tea that
   * moves nothing, and a meal comes back as nine items nobody would cook (D-167's "nineteen and a
   * half cups"). With it, an item has to earn its place.
   */
  item: 0.05,
  /**
   * What it costs to serve somebody the same food again later in the day.
   *
   * A price, not a ban: roti at lunch and again at dinner is how most of India eats. Chole bhature
   * twice in one day is not, and the first version of this search did exactly that because nothing
   * told it the day had a memory.
   */
  repeat: 0.25,
  /**
   * Fibre, and the reason a plan stops reading like a vending machine.
   *
   * `targets.fibreG` has been computed since the first version of the engine and the fill ignored
   * it, so a day could hit energy, protein and every ceiling on chole bhature, ghee and a cola —
   * each number correct, the food indefensible. Only a SHORTFALL costs anything: nobody was ever
   * harmed by an extra katori of dal.
   */
  /**
   * Added sugar, priced even BELOW the ceiling.
   *
   * The pack's `added_sugar_max_g` is a maximum, and a search that is only punished for crossing it
   * reads it as a budget to spend: a day came back with a glass of cola at dinner, 26 g of the
   * allowed 34 g, because cola closes an energy gap cheaply and nothing said it shouldn't. A cap
   * says "no more than this". This says "and less is better", which is what a person would say.
   */
  addedSugarSpend: 2,
  fibre: 4,
  /**
   * docs/04 §7: "every meal ≥ 20 g protein (or ≥ 0.25 g/kg ABW, whichever is greater) — except
   * snacks < 10 % of target, which need ≥ 10 g". `MealTarget.minProteinG` has carried that figure
   * since step 12 was written and the fill never read it, so a day could satisfy its protein target
   * with one meal and leave the others at naan and a banana. Weighted above the energy term,
   * because it is a rule rather than a preference.
   */
  proteinFloor: 14,
  /**
   * Composition (D-235): what fraction of the slot's structural requirements — "a cereal, a
   * protein source, a vegetable" — the meal has not met. Weighted like the protein floor,
   * because it is a rule from the pack, not a preference. Zero whenever the pack carries no
   * composition block, which is what keeps v1.0.0 output byte-identical.
   */
  composition: 10,
  /**
   * Saturated fat, likewise already a pack target (`saturatedFatMaxG`) that nothing consulted.
   * Over the ceiling only — this is what prices ghee against dal rather than banning it.
   */
  saturatedFat: 3,
} as const;

type Nutrients = {
  kcal: number;
  proteinG: number;
  fatG: number;
  carbG: number;
  fibreG: number;
  sodiumMg: number;
  addedSugarG: number;
  saturatedFatG: number;
};

const ZERO: Nutrients = {
  kcal: 0,
  proteinG: 0,
  fatG: 0,
  carbG: 0,
  fibreG: 0,
  sodiumMg: 0,
  addedSugarG: 0,
  saturatedFatG: 0,
};

/** A food, its serving, and what one increment of it does. Resolved once, before the search. */
type Candidate = {
  readonly food: EngineFood;
  readonly measure: EngineMeasure;
  /** Nutrition of ONE increment (half a serving on the default pack), not of 100 g. */
  readonly per: Nutrients;
};

/** The slot's composition rule, resolved to bitmasks: requirement i is met when bit i is set. */
type Composition = {
  readonly count: number;
  /** Per candidate, which requirements one serving of it satisfies. */
  readonly bits: readonly number[];
};

const NO_COMPOSITION: Composition = { count: 0, bits: [] };

/** Requirements a candidate list can satisfy for one slot, as bitmasks aligned with it. */
function compositionFor(
  slot: string,
  candidates: readonly Candidate[],
  pack: RulePack,
): Composition {
  const rule = pack.composition?.rules.find((r) => r.slots.includes(slot));
  if (rule === undefined) return NO_COMPOSITION;

  const bits = candidates.map((candidate) => {
    let mask = 0;
    for (const [index, wanted] of rule.require_one_of.entries()) {
      if (candidate.food.tags.some((tag) => wanted.includes(tag))) {
        mask |= 1 << index;
      }
    }
    return mask;
  });

  return { count: rule.require_one_of.length, bits };
}

function popcount(mask: number): number {
  let n = mask;
  let count = 0;
  while (n !== 0) {
    n &= n - 1;
    count += 1;
  }
  return count;
}

/** A meal being built: how many increments of each candidate, and where that leaves the totals. */
type State = {
  readonly counts: readonly number[];
  readonly totals: Nutrients;
  readonly items: number;
  /** How many of those items were already served earlier today. */
  readonly repeats: number;
  /** Which of the slot's composition requirements the meal so far satisfies (bitmask). */
  readonly covered: number;
  readonly cost: number;
};

function scale(food: EngineFood, grams: number): Nutrients {
  const factor = grams / 100;
  return {
    kcal: food.kcal * factor,
    proteinG: food.proteinG * factor,
    fatG: food.fatG * factor,
    carbG: food.carbG * factor,
    fibreG: food.fibreG * factor,
    sodiumMg: food.sodiumMg * factor,
    addedSugarG: food.addedSugarG * factor,
    saturatedFatG: food.saturatedFatG * factor,
  };
}

function add(a: Nutrients, b: Nutrients): Nutrients {
  return {
    kcal: a.kcal + b.kcal,
    proteinG: a.proteinG + b.proteinG,
    fatG: a.fatG + b.fatG,
    carbG: a.carbG + b.carbG,
    fibreG: a.fibreG + b.fibreG,
    sodiumMg: a.sodiumMg + b.sodiumMg,
    addedSugarG: a.addedSugarG + b.addedSugarG,
    saturatedFatG: a.saturatedFatG + b.saturatedFatG,
  };
}

/** The smallest step the plan may speak in, from the pack's rounding block. */
export function increment(pack: RulePack): number {
  return Math.min(...pack.rounding.household_increments);
}

/** Protein per kcal — the order the pool is kept in, so the search is fed its best options first. */
function proteinDensity(food: EngineFood): number {
  return food.kcal > 0 ? food.proteinG / food.kcal : 0;
}

/** Total order, so the same pool always fills the same way (rule 2: byte-identical output). */
function byProteinDensity(a: EngineFood, b: EngineFood): number {
  const delta = proteinDensity(b) - proteinDensity(a);
  return delta !== 0 ? delta : a.id.localeCompare(b.id);
}

/**
 * A meal's share of the day's ceilings, plus the day's remaining ceilings.
 *
 * Two numbers rather than one because they answer different questions: the SHARE is what a meal
 * ought to use, and costs something to exceed; the REMAINING is what the day has left, and cannot
 * be exceeded at all — that is docs/04 §8's assertion. A meal may borrow from a later meal's share
 * and pay for it in the cost function; it may not borrow from a cap that does not exist.
 */
type Allowance = {
  readonly proteinG: number;
  /** docs/04 §7's per-meal protein floor. Never more than the day still has to give. */
  readonly proteinFloorG: number;
  readonly fatG: number;
  readonly fibreG: number;
  readonly sodiumMg: number;
  readonly addedSugarG: number;
  readonly saturatedFatG: number;
  readonly sodiumHardMg: number;
  readonly addedSugarHardG: number;
};

function relative(actual: number, want: number): number {
  return (actual - want) / Math.max(want, 1);
}

function over(actual: number, ceiling: number): number {
  return Math.max(0, relative(actual, ceiling));
}

/** How far SHORT of a target something is, as a fraction. Being over costs nothing. */
function under(actual: number, want: number): number {
  return Math.max(0, -relative(actual, want));
}

function square(x: number): number {
  return x * x;
}

function costOf(
  totals: Nutrients,
  items: number,
  repeats: number,
  targetKcal: number,
  allowance: Allowance,
  composition: Composition = NO_COMPOSITION,
  covered = 0,
): number {
  const unmet =
    composition.count > 0
      ? (composition.count - popcount(covered)) / composition.count
      : 0;
  return (
    WEIGHT.composition * square(unmet) +
    WEIGHT.kcal * square(relative(totals.kcal, targetKcal)) +
    WEIGHT.protein * square(relative(totals.proteinG, allowance.proteinG)) +
    WEIGHT.fat * square(over(totals.fatG, allowance.fatG)) +
    WEIGHT.sodium * square(over(totals.sodiumMg, allowance.sodiumMg)) +
    WEIGHT.addedSugar *
      square(over(totals.addedSugarG, allowance.addedSugarG)) +
    WEIGHT.addedSugarSpend *
      square(totals.addedSugarG / Math.max(allowance.addedSugarG, 1)) +
    WEIGHT.proteinFloor *
      square(under(totals.proteinG, allowance.proteinFloorG)) +
    WEIGHT.fibre * square(under(totals.fibreG, allowance.fibreG)) +
    WEIGHT.saturatedFat *
      square(over(totals.saturatedFatG, allowance.saturatedFatG)) +
    WEIGHT.item * items +
    WEIGHT.repeat * repeats
  );
}

/**
 * The servings a search may reach for.
 *
 * A food with no measure cannot be served, and a food whose increment carries neither energy nor
 * protein cannot move this meal anywhere — water, green tea — so neither becomes a candidate. That
 * is cheaper and clearer than teaching the cost function to dislike them.
 */
function candidatesFrom(
  pool: readonly EngineFood[],
  step: number,
): Candidate[] {
  const out: Candidate[] = [];

  for (const food of pool) {
    const measure = food.measures[0];
    if (measure === undefined) continue;

    const per = scale(food, measure.grams * step);
    if (per.kcal <= 0 && per.proteinG <= 0) continue;

    out.push({ food, measure, per });
  }

  return out;
}

/**
 * Whether one more increment of [candidate] is allowed at all.
 *
 * These are refusals, not preferences: the per-occasion carbohydrate cap (docs/04 §7, diabetes),
 * the day's remaining sodium and added-sugar ceilings (docs/04 §8), and the per-food serving limit
 * that keeps a meal edible.
 */
function permitted(
  candidate: Candidate,
  state: State,
  index: number,
  constraints: Constraints,
  allowance: Allowance,
  step: number,
): boolean {
  const servings = ((state.counts[index] ?? 0) + 1) * step;
  if (servings > MAX_SERVINGS_PER_FOOD) return false;

  const next = add(state.totals, candidate.per);

  const carbCap = constraints.maxCarbGPerOccasion;
  if (carbCap !== undefined && next.carbG > carbCap) return false;

  return (
    next.sodiumMg <= allowance.sodiumHardMg &&
    next.addedSugarG <= allowance.addedSugarHardG
  );
}

/**
 * One meal, by beam search.
 *
 * Each level adds a single increment to every state in the beam, keeps the [BEAM_WIDTH] cheapest
 * distinct results, and remembers the best state ever seen. It stops early when the meal is inside
 * tolerance, or when [PATIENCE] levels pass without an improvement — a bounded search that usually
 * finishes long before its bound.
 */
function searchMeal(
  candidates: readonly Candidate[],
  targetKcal: number,
  allowance: Allowance,
  constraints: Constraints,
  step: number,
  tolerance: number,
  eatenToday: ReadonlySet<string>,
  composition: Composition,
): State {
  const empty: State = {
    counts: candidates.map(() => 0),
    totals: ZERO,
    items: 0,
    repeats: 0,
    covered: 0,
    cost: costOf(ZERO, 0, 0, targetKcal, allowance, composition, 0),
  };
  if (candidates.length === 0 || targetKcal <= 0) return empty;

  const within = (kcal: number): boolean =>
    Math.abs(kcal - targetKcal) <= targetKcal * tolerance;

  let beam: State[] = [empty];
  let best = empty;
  let stale = 0;

  for (let depth = 0; depth < MAX_INCREMENTS; depth += 1) {
    const children = new Map<string, State>();

    for (const state of beam) {
      for (const [index, candidate] of candidates.entries()) {
        if (!permitted(candidate, state, index, constraints, allowance, step)) {
          continue;
        }

        const counts = [...state.counts];
        const before = counts[index] ?? 0;
        counts[index] = before + 1;

        const fresh = before === 0;
        const totals = add(state.totals, candidate.per);
        const items = state.items + (fresh ? 1 : 0);
        const repeats =
          state.repeats + (fresh && eatenToday.has(candidate.food.id) ? 1 : 0);
        const covered = state.covered | (composition.bits[index] ?? 0);
        const child: State = {
          counts,
          totals,
          items,
          repeats,
          covered,
          cost: costOf(
            totals,
            items,
            repeats,
            targetKcal,
            allowance,
            composition,
            covered,
          ),
        };

        // The same multiset reached by a different order is the same meal. Without this the beam
        // fills up with permutations of itself and the search stops looking anywhere new.
        const key = signature(counts);
        const seen = children.get(key);
        if (seen === undefined || child.cost < seen.cost) {
          children.set(key, child);
        }
      }
    }

    if (children.size === 0) break;

    beam = [...children.values()]
      .sort(
        (a, b) =>
          a.cost - b.cost ||
          signature(a.counts).localeCompare(signature(b.counts)),
      )
      .slice(0, BEAM_WIDTH);

    const leader = beam[0];
    if (leader === undefined) break;

    if (leader.cost < best.cost) {
      best = leader;
      stale = 0;
    } else {
      stale += 1;
    }

    if (within(best.totals.kcal) && stale >= 1) break;
    if (stale >= PATIENCE) break;
  }

  return best;
}

/** A state's identity: which candidates, how many of each. Ties in the beam break on it. */
function signature(counts: readonly number[]): string {
  const parts: string[] = [];
  for (const [index, count] of counts.entries()) {
    if (count > 0) parts.push(`${index}:${count}`);
  }
  return parts.join(',');
}

export interface FillOptions {
  readonly mealTargets: readonly MealTarget[];
  readonly pool: readonly EngineFood[];
  readonly pack: RulePack;
  readonly constraints: Constraints;
  /// The DAY's protein target, shared out between the meals by energy split.
  readonly proteinTargetG: number;
  /// docs/04 §8 asserts `Σ sodium ≤ sodium_cap`, and the added-sugar cap is a target in its own
  /// right. Both are day ceilings the search may not cross — the added-sugar one is what keeps
  /// cola out of breakfast, without anybody having to declare cola a non-breakfast food (D-167).
  readonly sodiumMaxMg: number;
  readonly addedSugarMaxG: number;
  /// Both are pack targets the fill used to ignore (D-231). Fibre is aimed at; saturated fat is a
  /// ceiling. Between them they are what stops a nutritionally exact day made of cola and ghee.
  readonly fibreTargetG: number;
  readonly saturatedFatMaxG: number;
  /// Fat is a computed target, not a leftover. Without it the energy-closing phase reaches for the
  /// least protein-dense food available, which is pure fat: a day came back with 7.5 teaspoons of
  /// ghee at lunch and no cereal at all.
  readonly fatMaxG: number;
}

/**
 * One meal per target, filled in order, each one carrying what the last one left behind.
 *
 * The carry is what makes the DAY land rather than each meal separately: docs/04 §8 checks the
 * day's totals, and four meals each 3 % short is a day 3 % short — but four meals each 4 g short of
 * protein is a day 16 g short against a ±5 g assertion. Filling sequentially against what remains
 * spends the shortfall where there is still food to spend it on.
 */
export function fillMeals({
  mealTargets,
  pool,
  pack,
  constraints,
  proteinTargetG,
  sodiumMaxMg,
  addedSugarMaxG,
  fatMaxG,
  fibreTargetG,
  saturatedFatMaxG,
}: FillOptions): readonly Meal[] {
  const step = increment(pack);
  const candidates = candidatesFrom([...pool].sort(byProteinDensity), step);
  const tolerance = pack.validation.kcal_tolerance_pct;

  // What the day has already been served. The search pays a small price for reaching for it again,
  // which is what stops the same dish appearing at two meals.
  const eatenToday = new Set<string>();

  let remainingPct = mealTargets.reduce((sum, t) => sum + t.pct, 0);
  let remaining = {
    kcal: mealTargets.reduce((sum, t) => sum + t.kcal, 0),
    proteinG: proteinTargetG,
    fatG: fatMaxG,
    fibreG: fibreTargetG,
    sodiumMg: sodiumMaxMg,
    addedSugarG: addedSugarMaxG,
    saturatedFatG: saturatedFatMaxG,
  };

  return mealTargets.map((target) => {
    // What is left, split by what this meal is owed out of what is still owed. On the first meal
    // this is exactly its own share; on the last it is everything that remains.
    const share = remainingPct > 0 ? target.pct / remainingPct : 1;
    const targetKcal = Math.max(0, remaining.kcal * share);
    const allowance: Allowance = {
      proteinG: Math.max(0, remaining.proteinG * share),
      // The floor is a rule about this meal; the day's remaining protein is what there is left to
      // meet it with. Asking for more than remains would pull every later meal short.
      proteinFloorG: Math.max(
        0,
        Math.min(target.minProteinG, Math.max(0, remaining.proteinG)),
      ),
      fatG: Math.max(0, remaining.fatG * share),
      fibreG: Math.max(0, remaining.fibreG * share),
      sodiumMg: Math.max(0, remaining.sodiumMg * share),
      addedSugarG: Math.max(0, remaining.addedSugarG * share),
      saturatedFatG: Math.max(0, remaining.saturatedFatG * share),
      sodiumHardMg: Math.max(0, remaining.sodiumMg),
      addedSugarHardG: Math.max(0, remaining.addedSugarG),
    };

    const state = searchMeal(
      candidates,
      targetKcal,
      allowance,
      constraints,
      step,
      tolerance,
      eatenToday,
      compositionFor(target.slot, candidates, pack),
    );

    remainingPct -= target.pct;
    remaining = {
      kcal: remaining.kcal - state.totals.kcal,
      proteinG: remaining.proteinG - state.totals.proteinG,
      fatG: remaining.fatG - state.totals.fatG,
      fibreG: remaining.fibreG - state.totals.fibreG,
      sodiumMg: remaining.sodiumMg - state.totals.sodiumMg,
      addedSugarG: remaining.addedSugarG - state.totals.addedSugarG,
      saturatedFatG: remaining.saturatedFatG - state.totals.saturatedFatG,
    };

    for (const [index, count] of state.counts.entries()) {
      const candidate = candidates[index];
      if (count > 0 && candidate !== undefined)
        eatenToday.add(candidate.food.id);
    }

    const items = state.counts
      .map((count, index) => ({ count, candidate: candidates[index] }))
      .filter((p) => p.count > 0 && p.candidate !== undefined)
      .map((p) => toItem(p.candidate!, p.count * step));

    return {
      slot: target.slot,
      items,
      kcal: state.totals.kcal,
      proteinG: state.totals.proteinG,
      fatG: state.totals.fatG,
      carbG: state.totals.carbG,
      fibreG: state.totals.fibreG,
      sodiumMg: state.totals.sodiumMg,
      residualKcal: state.totals.kcal - target.kcal,
      approximated:
        Math.abs(state.totals.kcal - targetKcal) > targetKcal * tolerance,
    };
  });
}

function toItem(candidate: Candidate, quantity: number): MealItem {
  const grams = candidate.measure.grams * quantity;
  const n = scale(candidate.food, grams);

  return {
    foodId: candidate.food.id,
    name: candidate.food.name,
    measureLabel: candidate.measure.label,
    quantity,
    grams,
    kcal: n.kcal,
    proteinG: n.proteinG,
    fatG: n.fatG,
    carbG: n.carbG,
    fibreG: n.fibreG,
    sodiumMg: n.sodiumMg,
  };
}
