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

/** Solve one plate size. Same kcal target; smaller prefers dense / drinkable / no-prep. */
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
    targetKcal: input.targetKcal,
    targetProteinG: input.targetProteinG,
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
