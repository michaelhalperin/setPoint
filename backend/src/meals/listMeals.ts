import type { PrismaClient } from '@prisma/client';
import { localDateISO, localDayRange } from '../engine/index.js';
import type { PhotoStore } from '../photos/store.js';
import { toMealSummaries, type MealSummary } from './summary.js';

export type ListMealsDeps = {
  prisma: PrismaClient;
  /** Signs meal-photo URLs. Null/absent: stored photos are omitted. */
  photos?: PhotoStore | null;
  now?: Date;
};

export type MealsListView = {
  date: string;
  meals: MealSummary[];
};

const mealSelect = {
  id: true,
  loggedAt: true,
  kcal: true,
  proteinG: true,
  carbsG: true,
  fatG: true,
  source: true,
  rawInput: true,
  photoUrl: true,
  photoKey: true,
  notes: true,
  items: true,
  parseConfidence: true,
} as const;

export async function listMealsForDate(
  deps: ListMealsDeps,
  userId: string,
  dateISO?: string,
): Promise<MealsListView> {
  const now = deps.now ?? new Date();
  const user = await deps.prisma.user.findUnique({
    where: { id: userId },
    select: { timezone: true },
  });
  const timezone = user?.timezone ?? 'UTC';
  const date = dateISO ?? localDateISO(now, timezone);
  const { start, end } = localDayRange(date, timezone);

  const rows = await deps.prisma.meal.findMany({
    where: { userId, loggedAt: { gte: start, lt: end } },
    orderBy: { loggedAt: 'asc' },
    select: mealSelect,
  });

  return { date, meals: await toMealSummaries(rows, deps.photos ?? null, now) };
}
