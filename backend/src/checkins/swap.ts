import { DRINKABLE_SLUGS } from '../engine/appetite.js';
import { filterAllowedFoods, type SolverFood } from '../solver/index.js';

export type SwapAlternative = {
  slug: string;
  name: string;
  servingDesc: string;
  quantity: number;
  kcal: number;
  proteinG: number;
  /** Calories this plate gains (+) or loses (−) with the swap. */
  deltaKcal: number;
};

const MAX_ALTERNATIVES = 14;

/** Servings that bring `food` closest to `kcal`, in half servings, never absurd. */
export function swapQuantity(kcal: number, food: Pick<SolverFood, 'kcal'>): number {
  if (food.kcal <= 0) return 1;
  const halves = Math.round((kcal / food.kcal) * 2) / 2;
  return Math.min(3, Math.max(0.5, halves));
}

/**
 * Foods that can stand in for one item of a plate: the same kind (a drink for a drink, food for
 * food), nothing the person avoids, nothing already on the plate, each sized to roughly the
 * calories of what it replaces. Closest in calories first.
 */
export function alternativesFor(input: {
  foods: SolverFood[];
  excludedTokens: string[];
  /** The item being replaced. `slug` is null when its food isn't in the staple list any more. */
  current: { slug: string | null; kcal: number };
  /** Slugs already on the plate. */
  onPlate: string[];
}): SwapAlternative[] {
  const drink = input.current.slug ? DRINKABLE_SLUGS.has(input.current.slug) : false;
  const taken = new Set(input.onPlate);
  return filterAllowedFoods(input.foods, input.excludedTokens)
    .filter((food) => DRINKABLE_SLUGS.has(food.slug) === drink && !taken.has(food.slug))
    .map((food) => {
      const quantity = swapQuantity(input.current.kcal, food);
      const kcal = Math.round(food.kcal * quantity);
      return {
        slug: food.slug,
        name: food.name,
        servingDesc: food.servingDesc,
        quantity,
        kcal,
        proteinG: Math.round(food.proteinG * quantity * 10) / 10,
        deltaKcal: kcal - input.current.kcal,
      };
    })
    .sort((a, b) => Math.abs(a.deltaKcal) - Math.abs(b.deltaKcal))
    .slice(0, MAX_ALTERNATIVES);
}
