import type { PrismaClient } from '@prisma/client';
import type { PhotoStore } from '../photos/store.js';
import { toMealSummaries, type MealItem, type MealSummary } from './summary.js';

export class MealNotFoundError extends Error {}

export type UpdateMealInput = {
  summary: string;
  items: MealItem[];
};

export type UpdateMealDeps = {
  prisma: PrismaClient;
  /** Signs the meal's photo URL. Null/absent: a stored photo is omitted. */
  photos?: PhotoStore | null;
};

const round1 = (value: number): number => Math.round(value * 10) / 10;

export async function updateMeal(
  deps: UpdateMealDeps,
  userId: string,
  mealId: string,
  input: UpdateMealInput,
): Promise<MealSummary> {
  const existing = await deps.prisma.meal.findFirst({
    where: { id: mealId, userId },
  });
  if (!existing) throw new MealNotFoundError('meal not found');

  const items = input.items.map((item) => ({
    name: item.name.trim(),
    quantity: item.quantity.trim(),
    kcal: Math.round(item.kcal),
    proteinG: round1(item.proteinG),
    carbsG: round1(item.carbsG),
    fatG: round1(item.fatG),
  }));

  const updated = await deps.prisma.meal.update({
    where: { id: mealId },
    data: {
      rawInput: input.summary.trim(),
      items,
      kcal: items.reduce((total, item) => total + item.kcal, 0),
      proteinG: round1(items.reduce((total, item) => total + item.proteinG, 0)),
      carbsG: round1(items.reduce((total, item) => total + item.carbsG, 0)),
      fatG: round1(items.reduce((total, item) => total + item.fatG, 0)),
      parseConfidence: null,
      notes: null,
    },
  });

  const [summary] = await toMealSummaries([updated], deps.photos ?? null);
  return summary!;
}
