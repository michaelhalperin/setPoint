import type { PrismaClient } from '@prisma/client';
import { namedSummary, prescribe } from '../../solver/prescribe.js';
import { excludedTokensFor, loadStapleFoods } from '../../solver/meals.js';
import { STAPLE_FOODS } from '../../data/stapleFoods.js';
import type { PlateArgs } from './kinds.js';
import { sanitizeName, type NutritionSnapshot } from './snapshot.js';

export type PlateShape = { requireNoCook: boolean; requireDrinkable: boolean };

export function shapeFromMessage(message: string): PlateShape {
  const t = message.toLowerCase();
  const ten = /\b(10\s*min|ten\s*minutes|only have 10|אין לי זמן|10 דק)\b/i.test(t) || t.includes('10 דקות');
  const drink =
    /\b(drink|shake|smoothie)\b/i.test(t) || t.includes('לשתות') || t.includes('משהו שאפשר לשתות');
  return { requireNoCook: ten, requireDrinkable: drink };
}

export async function suggestPlate(
  prisma: PrismaClient,
  userId: string,
  snapshot: NutritionSnapshot,
  shape: PlateShape,
): Promise<PlateArgs | null> {
  let foods = STAPLE_FOODS;
  try {
    const loaded = await loadStapleFoods(prisma);
    if (loaded.solverFoods.length) foods = loaded.solverFoods;
  } catch {
    // Tests and a missing FoodItem table fall back to the curated list.
  }
  if (shape.requireDrinkable && !snapshot.drinkableOk) return null;
  const excluded = await excludedTokensFor(prisma, userId, snapshot.dislikedFoods);
  const targetKcal = Math.max(snapshot.remainingKcal, shape.requireDrinkable ? 150 : 300);
  const rx = prescribe(foods, {
    targetKcal,
    targetProteinG: snapshot.remainingProteinG,
    excludedTokens: excluded,
    pantryTokens: [],
    prepTimeMaxMin: shape.requireNoCook ? 10 : snapshot.prepTimeMaxMin,
    requireNoCook: shape.requireNoCook,
    requireDrinkable: shape.requireDrinkable,
    preferLowFriction: shape.requireNoCook,
    preferDrinkable: shape.requireDrinkable,
  });
  if (!rx) return null;
  return {
    kind: 'suggest_plate',
    localDate: snapshot.localDate,
    timezone: snapshot.timezone,
    targetKcal: rx.targetKcal,
    requireNoCook: shape.requireNoCook,
    requireDrinkable: shape.requireDrinkable,
    summary: namedSummary(rx),
    items: rx.items.map((i) => ({
      slug: i.slug,
      name: sanitizeName(i.name),
      servingDesc: sanitizeName(i.servingDesc),
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
