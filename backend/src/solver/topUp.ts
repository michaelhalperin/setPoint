import { filterAllowedFoods } from './exclusions.js';
import type { PrescriptionLineItem, PrescriptionResult, SolverFood } from './types.js';

/**
 * Add-ons: small, calorie-dense things you add to a meal you're already eating
 * or drink on the side — the "same bite, more calories" lever for people who
 * can't face a second plate. Order is the tie-break (earlier = preferred).
 */
export const ADD_ON_SLUGS = [
  'whole-milk',
  'peanut-butter',
  'almonds',
  'olive-oil',
  'medjool-dates',
  'chocolate-milk',
  'granola',
  'avocado',
  'trail-mix',
  'cashews',
  'kefir',
  'ready-protein-shake',
  'cheddar-cheese',
  'almond-butter',
  'tahini',
  'butter',
] as const;

const DRINKS = new Set(['whole-milk', 'chocolate-milk', 'kefir', 'ready-protein-shake']);

export const TOP_UP_CONFIG = {
  /** Most servings of one add-on. */
  maxQty: 2,
  /** A top-up that lands below this share of the ask isn't worth showing. */
  minShare: 0.5,
  /** Penalty (kcal-equivalent) for a second item — one thing is easier. */
  secondItemPenalty: 60,
  /** Bonus (kcal-equivalent) for a drink when drinks are welcome. */
  drinkBonus: 30,
} as const;

type Option = { food: SolverFood; qty: number; kcal: number; rank: number };

const round1 = (n: number): number => Math.round(n * 10) / 10;

/**
 * One or two add-ons that land closest to `targetKcal` without ever breaking a
 * restriction. Deterministic: ties break on the add-on order. Null when no
 * add-on fits (every option excluded, or nothing gets near the ask).
 */
export function pickTopUp(
  foods: SolverFood[],
  input: { targetKcal: number; excludedTokens: string[]; drinkableOk?: boolean },
): PrescriptionResult | null {
  const rankOf = new Map<string, number>(ADD_ON_SLUGS.map((slug, i) => [slug, i]));
  const allowed = filterAllowedFoods(
    foods.filter((f) => rankOf.has(f.slug)),
    input.excludedTokens,
  );
  if (allowed.length === 0 || input.targetKcal <= 0) return null;

  const options: Option[] = [];
  for (const food of allowed) {
    for (let qty = 1; qty <= TOP_UP_CONFIG.maxQty; qty += 1) {
      options.push({ food, qty, kcal: food.kcal * qty, rank: rankOf.get(food.slug)! });
    }
  }

  const drinkOk = input.drinkableOk ?? true;
  const cost = (combo: Option[]): number => {
    const kcal = combo.reduce((a, o) => a + o.kcal, 0);
    // Undershooting is worse than a little over: the point is eating enough.
    const miss = kcal >= input.targetKcal ? kcal - input.targetKcal : (input.targetKcal - kcal) * 1.5;
    const extra = combo.length > 1 ? TOP_UP_CONFIG.secondItemPenalty : 0;
    const drink = drinkOk && combo.some((o) => DRINKS.has(o.food.slug)) ? TOP_UP_CONFIG.drinkBonus : 0;
    const order = combo.reduce((a, o) => a + o.rank, 0) * 0.5;
    return miss + extra - drink + order;
  };

  let best: Option[] | null = null;
  let bestCost = Number.POSITIVE_INFINITY;
  const consider = (combo: Option[]) => {
    const c = cost(combo);
    if (c < bestCost) {
      best = combo;
      bestCost = c;
    }
  };
  for (let i = 0; i < options.length; i += 1) {
    consider([options[i]!]);
    for (let j = i + 1; j < options.length; j += 1) {
      if (options[j]!.food.slug === options[i]!.food.slug) continue;
      consider([options[i]!, options[j]!]);
    }
  }
  if (!best) return null;
  const chosen: Option[] = best;
  const totalKcal = chosen.reduce((a, o) => a + o.kcal, 0);
  if (totalKcal < input.targetKcal * TOP_UP_CONFIG.minShare) return null;

  const items: PrescriptionLineItem[] = [...chosen]
    .sort((a, b) => a.rank - b.rank)
    .map((o) => ({
      slug: o.food.slug,
      name: o.food.name,
      servingDesc: o.food.servingDesc,
      quantity: o.qty,
      unit: 'serving',
      kcal: Math.round(o.kcal),
      proteinG: round1(o.food.proteinG * o.qty),
      carbsG: round1(o.food.carbsG * o.qty),
      fatG: round1(o.food.fatG * o.qty),
    }));
  return {
    items,
    totalKcal: items.reduce((a, i) => a + i.kcal, 0),
    totalProteinG: round1(items.reduce((a, i) => a + i.proteinG, 0)),
    totalCarbsG: round1(items.reduce((a, i) => a + i.carbsG, 0)),
    totalFatG: round1(items.reduce((a, i) => a + i.fatG, 0)),
    targetKcal: input.targetKcal,
    targetProteinG: null,
  };
}
