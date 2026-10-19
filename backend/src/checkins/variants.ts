import { prescribe, type SolverFood } from '../solver/index.js';

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
  const rx = prescribe(input.foods, {
    targetKcal: variantMealTarget(input.targetKcal, input.variant),
    targetProteinG: variantProteinTarget(input.targetProteinG, input.variant),
    excludedTokens: input.excludedTokens,
    pantryTokens: input.pantryTokens,
    prepTimeMaxMin: input.prepTimeMaxMin,
    ...prefs,
  });
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
