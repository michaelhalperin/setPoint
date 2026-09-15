import type { PrismaClient } from '@prisma/client';
import { localDateISO, msSinceLocalMidnight, shiftDateISO, startOfLocalDay } from '../engine/time.js';
import { buildAppetiteHistory, historyWindow, type AppetiteHistory, type AppetiteLevel } from './history.js';

export async function loadAppetiteHistory(
  prisma: PrismaClient,
  userId: string,
  now = new Date(),
): Promise<AppetiteHistory> {
  const user = await prisma.user.findUnique({
    where: { id: userId },
    include: { onboarding: { select: { dailyKcalTarget: true } } },
  });
  if (!user?.onboarding) {
    return buildAppetiteHistory({
      todayISO: localDateISO(now, 'UTC'),
      targetKcal: 2500,
      levels: {},
      consumedByDate: {},
      lastMealMinByDate: {},
      workoutDates: [],
      lowDayPrescriptions: [],
    });
  }

  const timezone = user.timezone;
  const todayISO = localDateISO(now, timezone);
  const dates = historyWindow(todayISO);
  const windowStartISO = dates[0]!;
  // Pull a little earlier for "before smaller plates" + late-dinner previous day.
  const fetchStartISO = shiftDateISO(windowStartISO, -14);
  const windowStart = startOfLocalDay(new Date(`${fetchStartISO}T12:00:00.000Z`), timezone);

  const [appetiteRows, meals, workouts, prescriptions] = await Promise.all([
    prisma.dayAppetite.findMany({
      where: { userId, localDate: { gte: fetchStartISO } },
      select: { localDate: true, level: true },
    }),
    prisma.meal.findMany({
      where: { userId, loggedAt: { gte: windowStart, lte: now } },
      select: { loggedAt: true, kcal: true },
    }),
    prisma.workout.findMany({
      where: { userId, start: { gte: windowStart, lte: now } },
      select: { start: true },
    }),
    prisma.prescription.findMany({
      where: { userId, createdAt: { gte: windowStart, lte: now } },
      select: {
        status: true,
        createdAt: true,
        items: { select: { name: true, foodItemId: true, foodItem: { select: { slug: true, tags: true } } } },
      },
    }),
  ]);

  const levels: Record<string, AppetiteLevel> = {};
  for (const row of appetiteRows) {
    if (row.level === 'HUNGRY' || row.level === 'NORMAL' || row.level === 'LOW') {
      levels[row.localDate] = row.level;
    }
  }

  const consumedByDate: Record<string, number> = {};
  const lastMealMinByDate: Record<string, number> = {};
  for (const meal of meals) {
    const iso = localDateISO(meal.loggedAt, timezone);
    consumedByDate[iso] = (consumedByDate[iso] ?? 0) + meal.kcal;
    const min = Math.floor(msSinceLocalMidnight(meal.loggedAt, timezone) / 60_000);
    lastMealMinByDate[iso] = Math.max(lastMealMinByDate[iso] ?? 0, min);
  }

  const workoutDates = [...new Set(workouts.map((w) => localDateISO(w.start, timezone)))];

  const lowDayPrescriptions = prescriptions.map((rx) => ({
    date: localDateISO(rx.createdAt, timezone),
    accepted: rx.status === 'ACCEPTED',
    items: rx.items.map((item) => ({
      name: item.name,
      slug: item.foodItem?.slug ?? null,
      tags: item.foodItem?.tags ?? [],
    })),
  }));

  return buildAppetiteHistory({
    todayISO,
    targetKcal: user.onboarding.dailyKcalTarget,
    levels,
    consumedByDate,
    lastMealMinByDate,
    workoutDates,
    lowDayPrescriptions,
  });
}
