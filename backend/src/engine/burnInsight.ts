import type { PrismaClient } from '@prisma/client';
import { OnboardingIncompleteError } from '../dashboard/home.js';
import { localDateISO, shiftDateISO, startOfLocalDay } from './time.js';
import {
  EXPENDITURE_WINDOW_DAYS,
  estimateExpenditure,
  weeklyIntakeBars,
  type DailyIntake,
} from './expenditure.js';

export async function buildBurnInsight(
  prisma: PrismaClient,
  userId: string,
  now = new Date(),
): Promise<{
  version: string;
  ready: boolean;
  reason: string | null;
  burnKcal: number | null;
  rangeLow: number | null;
  rangeHigh: number | null;
  avgIntakeKcal: number | null;
  slopeKgPerDay: number | null;
  loggedDays: number;
  windowDays: number;
  weighIns: number;
  planKcal: number;
  weeks: { weekStart: string; intakeKcal: number; burnKcal: number | null; burnLow: number | null; burnHigh: number | null }[];
}> {
  const user = await prisma.user.findUnique({
    where: { id: userId },
    include: { onboarding: true },
  });
  if (!user?.onboarding) throw new OnboardingIncompleteError('onboarding not complete');

  const timezone = user.timezone;
  const todayISO = localDateISO(now, timezone);
  const startISO = shiftDateISO(todayISO, -(EXPENDITURE_WINDOW_DAYS - 1));
  const windowStart = startOfLocalDay(new Date(`${startISO}T12:00:00.000Z`), timezone);

  const [meals, weights] = await Promise.all([
    prisma.meal.findMany({
      where: { userId, loggedAt: { gte: windowStart, lte: now } },
      select: { loggedAt: true, kcal: true },
    }),
    prisma.weightEntry.findMany({
      where: { userId, measuredAt: { gte: windowStart, lte: now } },
      select: { measuredAt: true, weightKg: true },
      orderBy: { measuredAt: 'asc' },
    }),
  ]);

  const byDate = new Map<string, number>();
  for (let i = 0; i < EXPENDITURE_WINDOW_DAYS; i += 1) {
    byDate.set(shiftDateISO(startISO, i), 0);
  }
  for (const meal of meals) {
    const iso = localDateISO(meal.loggedAt, timezone);
    if (!byDate.has(iso)) continue;
    byDate.set(iso, (byDate.get(iso) ?? 0) + meal.kcal);
  }
  const days: DailyIntake[] = [...byDate.entries()].map(([date, kcal]) => ({ date, kcal }));
  const estimate = estimateExpenditure({
    days,
    weighIns: weights.map((w) => ({ at: w.measuredAt, kg: w.weightKg })),
  });
  const band =
    estimate.ready && estimate.burnKcal != null && estimate.rangeLow != null && estimate.rangeHigh != null
      ? { burnKcal: estimate.burnKcal, rangeLow: estimate.rangeLow, rangeHigh: estimate.rangeHigh }
      : null;

  return {
    ...estimate,
    planKcal: user.onboarding.dailyKcalTarget,
    weeks: weeklyIntakeBars(days, band),
  };
}
