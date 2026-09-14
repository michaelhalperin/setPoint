import type { PrismaClient } from '@prisma/client';
import { currentMealSlot, type MealTimes, type SlotName } from '../engine/mealSchedule.js';
import { mealItemsSchema, totalsFromItems, type MealItemInput } from '../meals/items.js';
import type { PrescriptionResult } from '../solver/types.js';

export const SUGGEST_SLOTS = ['breakfast', 'lunch', 'dinner'] as const;
export type SuggestSlot = (typeof SUGGEST_SLOTS)[number];

export class SavedMealNotFoundError extends Error {}

export type SavedMealView = {
  id: string;
  name: string;
  items: MealItemInput[];
  kcal: number;
  proteinG: number;
  carbsG: number;
  fatG: number;
  suggestSlot: SuggestSlot | null;
  useInCheckIns: boolean;
  lastUsedAt: string | null;
  useCount: number;
  suggested: boolean;
};

export type SavedMealWrite = {
  name: string;
  items: MealItemInput[];
  suggestSlot?: SuggestSlot | null;
  useInCheckIns?: boolean;
};

type SavedMealRow = {
  id: string;
  name: string;
  items: unknown;
  kcal: number;
  proteinG: number;
  carbsG: number;
  fatG: number;
  suggestSlot: string | null;
  useInCheckIns: boolean;
  lastUsedAt: Date | null;
  useCount: number;
};

export function parseSuggestSlot(value: string | null | undefined): SuggestSlot | null {
  if (value == null || value === '') return null;
  return SUGGEST_SLOTS.includes(value as SuggestSlot) ? (value as SuggestSlot) : null;
}

/**
 * Among meals tagged for `slot`, pick the one used most recently (then most
 * often). Null when none match the current window.
 */
export function pickSuggestedId(
  meals: { id: string; suggestSlot: string | null; lastUsedAt: Date | null; useCount: number }[],
  slot: SlotName,
): string | null {
  const matches = meals.filter((m) => m.suggestSlot === slot);
  if (matches.length === 0) return null;
  return [...matches].sort((a, b) => {
    const aTime = a.lastUsedAt?.getTime() ?? 0;
    const bTime = b.lastUsedAt?.getTime() ?? 0;
    if (aTime !== bTime) return bTime - aTime;
    return b.useCount - a.useCount;
  })[0]!.id;
}

export function serializeSavedMeal(row: SavedMealRow, suggestedId: string | null): SavedMealView {
  const items = mealItemsSchema.catch([]).parse(row.items);
  return {
    id: row.id,
    name: row.name,
    items,
    kcal: row.kcal,
    proteinG: row.proteinG,
    carbsG: row.carbsG,
    fatG: row.fatG,
    suggestSlot: parseSuggestSlot(row.suggestSlot),
    useInCheckIns: row.useInCheckIns,
    lastUsedAt: row.lastUsedAt?.toISOString() ?? null,
    useCount: row.useCount,
    suggested: row.id === suggestedId,
  };
}

export async function listSavedMeals(
  prisma: PrismaClient,
  userId: string,
  input: { nowMin: number; times: MealTimes },
): Promise<SavedMealView[]> {
  const rows = await prisma.savedMeal.findMany({
    where: { userId },
    orderBy: [{ lastUsedAt: 'desc' }, { useCount: 'desc' }, { createdAt: 'desc' }],
  });
  const slot = currentMealSlot(input.nowMin, input.times);
  const suggestedId = pickSuggestedId(rows, slot);
  const suggestedFirst = [...rows].sort((a, b) => Number(b.id === suggestedId) - Number(a.id === suggestedId));
  return suggestedFirst.map((row) => serializeSavedMeal(row, suggestedId));
}

export async function createSavedMeal(
  prisma: PrismaClient,
  userId: string,
  input: SavedMealWrite,
): Promise<SavedMealView> {
  const items = mealItemsSchema.parse(input.items);
  const totals = totalsFromItems(items);
  const row = await prisma.savedMeal.create({
    data: {
      userId,
      name: input.name.trim(),
      items,
      ...totals,
      suggestSlot: input.suggestSlot ?? null,
      useInCheckIns: input.useInCheckIns ?? false,
    },
  });
  return serializeSavedMeal(row, null);
}

export async function updateSavedMeal(
  prisma: PrismaClient,
  userId: string,
  id: string,
  input: SavedMealWrite,
): Promise<SavedMealView> {
  const existing = await prisma.savedMeal.findFirst({ where: { id, userId } });
  if (!existing) throw new SavedMealNotFoundError('saved meal not found');
  const items = mealItemsSchema.parse(input.items);
  const totals = totalsFromItems(items);
  const row = await prisma.savedMeal.update({
    where: { id },
    data: {
      name: input.name.trim(),
      items,
      ...totals,
      suggestSlot: input.suggestSlot ?? null,
      useInCheckIns: input.useInCheckIns ?? false,
    },
  });
  return serializeSavedMeal(row, null);
}

export async function deleteSavedMeal(prisma: PrismaClient, userId: string, id: string): Promise<void> {
  const result = await prisma.savedMeal.deleteMany({ where: { id, userId } });
  if (result.count === 0) throw new SavedMealNotFoundError('saved meal not found');
}

export async function getSavedMeal(prisma: PrismaClient, userId: string, id: string): Promise<SavedMealRow> {
  const row = await prisma.savedMeal.findFirst({ where: { id, userId } });
  if (!row) throw new SavedMealNotFoundError('saved meal not found');
  return row;
}

/** Snapshot a usual plate as the check-in suggestion for that slot. */
export function prescriptionFromSavedMeal(
  meal: Pick<SavedMealRow, 'name' | 'items' | 'kcal' | 'proteinG' | 'carbsG' | 'fatG'>,
  target: { targetKcal: number; targetProteinG: number | null },
): PrescriptionResult {
  const parsed = mealItemsSchema.catch([]).parse(meal.items);
  const items =
    parsed.length > 0
      ? parsed
      : [
          {
            name: meal.name,
            quantity: '1',
            kcal: meal.kcal,
            proteinG: meal.proteinG,
            carbsG: meal.carbsG,
            fatG: meal.fatG,
          },
        ];
  return {
    items: items.map((item) => ({
      slug: '',
      name: item.name,
      servingDesc: item.quantity || '1 serving',
      quantity: 1,
      unit: item.quantity || 'serving',
      kcal: item.kcal,
      proteinG: item.proteinG,
      carbsG: item.carbsG,
      fatG: item.fatG,
    })),
    totalKcal: meal.kcal,
    totalProteinG: meal.proteinG,
    totalCarbsG: meal.carbsG,
    totalFatG: meal.fatG,
    targetKcal: target.targetKcal,
    targetProteinG: target.targetProteinG,
  };
}
