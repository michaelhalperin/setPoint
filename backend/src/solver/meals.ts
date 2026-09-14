import type { PrismaClient } from '@prisma/client';
import { prescribe } from './prescribe.js';
import type { PrescriptionResult, SolverFood } from './types.js';

export type StapleFoods = {
  solverFoods: SolverFood[];
  foodIdBySlug: Map<string, string>;
};

/** The curated staple list the solver picks from, as stored in the database. */
export async function loadStapleFoods(prisma: Pick<PrismaClient, 'foodItem'>): Promise<StapleFoods> {
  const rows = await prisma.foodItem.findMany({ where: { isStaple: true } });
  return {
    solverFoods: rows.map((f) => ({
      slug: f.slug,
      name: f.name,
      servingDesc: f.servingDesc,
      kcal: f.kcal,
      proteinG: f.proteinG,
      carbsG: f.carbsG,
      fatG: f.fatG,
      tags: f.tags,
      allergens: f.allergens,
    })),
    foodIdBySlug: new Map(rows.map((f) => [f.slug, f.id])),
  };
}

/** Hard exclusions (allergens, diets, custom restrictions) plus disliked foods. */
export function excludedTokensFrom(restrictions: { token: string }[], dislikedFoods: string[] | null | undefined): string[] {
  return [...restrictions.map((r) => r.token), ...(dislikedFoods ?? [])];
}

export async function excludedTokensFor(
  prisma: Pick<PrismaClient, 'dietaryRestriction'>,
  userId: string,
  dislikedFoods: string[] | null | undefined,
): Promise<string[]> {
  const restrictions = await prisma.dietaryRestriction.findMany({
    where: { userId, isHardExclusion: true },
    select: { token: true },
  });
  return excludedTokensFrom(restrictions, dislikedFoods);
}

export const REFUEL_TARGET_KCAL = 340;
export const REFUEL_TARGET_PROTEIN_G = 25;

/** Post-workout (and pre-workout) snack: quick, protein-forward, and always inside the user's restrictions. */
export function refuelPrescription(foods: SolverFood[], excludedTokens: string[]): PrescriptionResult | null {
  if (foods.length === 0) return null;
  return prescribe(foods, {
    targetKcal: REFUEL_TARGET_KCAL,
    targetProteinG: REFUEL_TARGET_PROTEIN_G,
    excludedTokens,
    preferLowFriction: true,
  });
}
