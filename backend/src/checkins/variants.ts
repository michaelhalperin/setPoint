import { prescribe, SOLVER_CONFIG, type SolverFood } from '../solver/index.js';

export type CheckInVariant = 'full' | 'smaller';

export type VariantItem = {
  foodItemId: string | null;
  name: string;
  quantity: number;
  kcal: number;
  proteinG: number;
  carbsG: number;
  fatG: number;
};

export type VariantTotals = {
  kcal: number;
  proteinG: number;
  carbsG: number;
  fatG: number;
};

export type SolvedVariant = {
  items: VariantItem[];
  totals: VariantTotals;
};

/**
 * Drinks are judged differently from a plate: protein density alone would hand out three scoops of
 * whey in water, so protein counts for less, a second drink costs nothing extra, and no drink is
 * repeated more than twice. What's left is a smoothie, or milk and a shake.
 */
const DRINK_CONFIG = { ...SOLVER_CONFIG, maxQtyPerItem: 2, perItemPenalty: 60, proteinWeight: 1 } as unknown as typeof SOLVER_CONFIG;

/** Powder stirred into water: a way to add protein, not a drink to be handed to someone. Used only when nothing else fits. */
const POWDER_SLUGS = new Set(['whey-protein-shake', 'plant-protein-shake']);

export function variantSolverPrefs(variant: CheckInVariant, drinkableOk: boolean) {
  const smaller = variant === 'smaller';
  return {
    preferLowFriction: smaller,
    preferCalorieDense: smaller,
    preferDrinkable: smaller && drinkableOk,
  };
}

/** Not hungry ≈ half the full plate, floored so it stays a real bite. */
export function variantMealTarget(fullTargetKcal: number, variant: CheckInVariant): number {
  if (variant === 'full') return fullTargetKcal;
  return Math.max(200, Math.round((fullTargetKcal * 0.5) / 10) * 10);
}

export function variantProteinTarget(
  fullProteinG: number | null,
  variant: CheckInVariant,
): number | null {
  if (fullProteinG == null) return null;
  if (variant === 'full') return fullProteinG;
  return Math.max(10, Math.round(fullProteinG * 0.5));
}

/** Solve one plate size. Smaller uses ~half the kcal and denser / drinkable prefs. */
export function solveCheckInVariant(input: {
  foods: SolverFood[];
  foodIdBySlug: Map<string, string>;
  targetKcal: number;
  targetProteinG: number | null;
  excludedTokens: string[];
  pantryTokens: string[];
  prepTimeMaxMin: number | null;
  drinkableOk: boolean;
  variant: CheckInVariant;
}): SolvedVariant | null {
  const prefs = variantSolverPrefs(input.variant, input.drinkableOk);
  const constraints = {
    targetKcal: variantMealTarget(input.targetKcal, input.variant),
    targetProteinG: variantProteinTarget(input.targetProteinG, input.variant),
    excludedTokens: input.excludedTokens,
    pantryTokens: input.pantryTokens,
    prepTimeMaxMin: input.prepTimeMaxMin,
    ...prefs,
  };
  // The Drink plate is things you drink — milk, shakes, smoothies — not food that merely travels
  // well. Only when nothing drinkable fits what the person avoids does it fall back to the softer
  // preference rather than leave them without a plate.
  const drinks = { ...constraints, requireDrinkable: true };
  const rx =
    (prefs.preferDrinkable
      ? (prescribe(input.foods.filter((f) => !POWDER_SLUGS.has(f.slug)), drinks, DRINK_CONFIG) ??
        prescribe(input.foods, drinks, DRINK_CONFIG))
      : null) ?? prescribe(input.foods, constraints);
  if (!rx) return null;
  return {
    items: rx.items.map((i) => ({
      foodItemId: input.foodIdBySlug.get(i.slug) ?? null,
      name: i.name,
      quantity: i.quantity,
      kcal: i.kcal,
      proteinG: i.proteinG,
      carbsG: i.carbsG,
      fatG: i.fatG,
    })),
    totals: {
      kcal: rx.totalKcal,
      proteinG: rx.totalProteinG,
      carbsG: rx.totalCarbsG,
      fatG: rx.totalFatG,
    },
  };
}

export function publicPrescription(solved: SolvedVariant, id: string) {
  return {
    id,
    totalKcal: solved.totals.kcal,
    totalProteinG: solved.totals.proteinG,
    items: solved.items.map((i) => ({
      name: i.name,
      quantity: i.quantity,
      kcal: i.kcal,
      proteinG: i.proteinG,
    })),
  };
}
