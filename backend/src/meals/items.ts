import { z } from 'zod';

const round1 = (n: number): number => Math.round(n * 10) / 10;

export const mealItemSchema = z.object({
  name: z.string().trim().min(1).max(120),
  quantity: z.string().trim().max(80).default(''),
  kcal: z.number().int().min(0).max(5000),
  proteinG: z.number().min(0).max(1000),
  carbsG: z.number().min(0).max(1000),
  fatG: z.number().min(0).max(1000),
});

export const mealItemsSchema = z.array(mealItemSchema).min(1).max(20);

export type MealItemInput = z.infer<typeof mealItemSchema>;

export type MealTotals = {
  kcal: number;
  proteinG: number;
  carbsG: number;
  fatG: number;
};

/** Totals are always derived from items so a client cannot send a mismatched target. */
export function totalsFromItems(items: MealItemInput[]): MealTotals {
  return {
    kcal: items.reduce((sum, item) => sum + item.kcal, 0),
    proteinG: round1(items.reduce((sum, item) => sum + item.proteinG, 0)),
    carbsG: round1(items.reduce((sum, item) => sum + item.carbsG, 0)),
    fatG: round1(items.reduce((sum, item) => sum + item.fatG, 0)),
  };
}
