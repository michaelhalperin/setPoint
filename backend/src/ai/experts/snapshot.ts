import type { PrismaClient } from '@prisma/client';
import { localDateISO, startOfLocalDay } from '../../engine/index.js';
import { excludedTokensFor } from '../../solver/meals.js';

export type NutritionSnapshot = {
  lang: 'en' | 'he';
  timezone: string;
  localDate: string;
  goal: string;
  remainingKcal: number;
  targetKcal: number;
  consumedKcal: number;
  remainingProteinG: number | null;
  restrictions: string[];
  dislikedFoods: string[];
  prepTimeMaxMin: number | null;
  drinkableOk: boolean;
  savedMeals: { name: string; kcal: number }[];
  todayMeals: { name: string; kcal: number }[];
  recentDays: { date: string; kcal: number }[];
  trainingBumpKcal: number | null;
};

const MAX_SAVED = 8;
const MAX_TODAY = 8;
const MAX_DAYS = 7;

/** Daily snapshot is authoritative over transcript history. Compact on purpose. */
export async function assembleSnapshot(
  prisma: PrismaClient,
  userId: string,
  lang: 'en' | 'he',
  now = new Date(),
): Promise<NutritionSnapshot | null> {
  const user = await prisma.user.findUnique({
    where: { id: userId },
    select: {
      timezone: true,
      onboarding: {
        select: {
          goal: true,
          dailyKcalTarget: true,
          dailyProteinTargetG: true,
          dislikedFoods: true,
          prepTimeMaxMin: true,
          drinkableOk: true,
        },
      },
    },
  });
  if (!user?.onboarding) return null;

  const tz = user.timezone || 'UTC';
  const localDate = localDateISO(now, tz);
  const start = startOfLocalDay(now, tz);
  const weekAgo = new Date(start.getTime() - MAX_DAYS * 86_400_000);

  const [meals, saved, excluded, workouts] = await Promise.all([
    prisma.meal.findMany({
      where: { userId, loggedAt: { gte: weekAgo } },
      select: { loggedAt: true, kcal: true, proteinG: true, rawInput: true, source: true },
      orderBy: { loggedAt: 'desc' },
      take: 40,
    }),
    prisma.savedMeal.findMany({
      where: { userId },
      select: { name: true, kcal: true },
      orderBy: { useCount: 'desc' },
      take: MAX_SAVED,
    }),
    excludedTokensFor(prisma, userId, user.onboarding.dislikedFoods),
    prisma.workout.findMany({
      where: { userId, start: { gte: start } },
      select: { activeKcal: true },
    }),
  ]);

  const todayMeals = meals.filter((m) => m.loggedAt >= start);
  const consumedKcal = todayMeals.reduce((s, m) => s + m.kcal, 0);
  const consumedProteinG = todayMeals.reduce((s, m) => s + m.proteinG, 0);
  const targetKcal = user.onboarding.dailyKcalTarget;
  const remainingKcal = Math.max(0, targetKcal - consumedKcal);
  const proteinTarget = user.onboarding.dailyProteinTargetG;
  const bump = workouts.reduce((s, w) => s + (w.activeKcal ?? 0), 0);

  const byDate = new Map<string, number>();
  for (const m of meals) {
    const d = localDateISO(m.loggedAt, tz);
    byDate.set(d, (byDate.get(d) ?? 0) + m.kcal);
  }

  return {
    lang,
    timezone: tz,
    localDate,
    goal: user.onboarding.goal,
    remainingKcal,
    targetKcal,
    consumedKcal,
    remainingProteinG: proteinTarget == null ? null : Math.max(0, proteinTarget - consumedProteinG),
    restrictions: excluded,
    dislikedFoods: user.onboarding.dislikedFoods ?? [],
    prepTimeMaxMin: user.onboarding.prepTimeMaxMin,
    drinkableOk: user.onboarding.drinkableOk ?? true,
    savedMeals: saved.map((s) => ({ name: s.name.slice(0, 40), kcal: s.kcal })),
    todayMeals: todayMeals.slice(0, MAX_TODAY).map((m) => ({
      name: (m.rawInput ?? m.source).slice(0, 40),
      kcal: m.kcal,
    })),
    recentDays: [...byDate.entries()]
      .sort((a, b) => b[0].localeCompare(a[0]))
      .slice(0, MAX_DAYS)
      .map(([date, kcal]) => ({ date, kcal })),
    trainingBumpKcal: bump > 0 ? bump : null,
  };
}

export function sanitizeName(raw: string): string {
  return raw.replace(/[\n\r]/g, ' ').replace(/\s+/g, ' ').trim().slice(0, 40);
}
