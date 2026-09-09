import type { PrismaClient } from '@prisma/client';
import { localDateISO, shiftDateISO, startOfLocalDay, type Goal } from '../engine/index.js';
import { classifyDay, type DayKind } from './classify.js';
import { OnboardingIncompleteError } from './home.js';

export type SettlementDeps = {
  prisma: PrismaClient;
  now?: Date;
};

export type SettlementDay = {
  date: string;
  kind: DayKind;
  kcalConsumed: number;
  kcalTarget: number;
  summaryLine: string | null;
};

export type SettlementView = {
  days: SettlementDay[];
  today: {
    date: string;
    kind: DayKind;
    kcalConsumed: number;
    kcalTarget: number;
    provisional: true;
  };
  weekSummary: string;
};

const WINDOW_DAYS = 7;

export async function buildSettlement(deps: SettlementDeps, userId: string): Promise<SettlementView> {
  const now = deps.now ?? new Date();
  const { prisma } = deps;

  const user = await prisma.user.findUnique({
    where: { id: userId },
    include: { onboarding: true },
  });
  if (!user?.onboarding) throw new OnboardingIncompleteError('onboarding not complete');

  const goal = user.onboarding.goal as Goal;
  const targetKcal = user.onboarding.dailyKcalTarget;

  const todayISO = localDateISO(now, user.timezone);
  const windowStartISO = shiftDateISO(todayISO, -(WINDOW_DAYS - 1));

  const rows = await prisma.dayOutcome.findMany({
    where: { userId, date: { gte: new Date(`${windowStartISO}T00:00:00.000Z`), lt: new Date(`${todayISO}T00:00:00.000Z`) } },
    orderBy: { date: 'asc' },
  });

  const days: SettlementDay[] = rows.map((r) => ({
    date: r.date.toISOString().slice(0, 10),
    kind: r.kind as DayKind,
    kcalConsumed: r.kcalConsumed,
    kcalTarget: r.kcalTarget,
    summaryLine: r.summaryLine,
  }));

  // Today, live (not yet settled).
  const todayMeals = await prisma.meal.findMany({
    where: { userId, loggedAt: { gte: startOfLocalDay(now, user.timezone) } },
    select: { kcal: true },
  });
  const todayKcal = todayMeals.reduce((acc, m) => acc + m.kcal, 0);

  return {
    days,
    today: {
      date: todayISO,
      kind: classifyDay(todayKcal, targetKcal),
      kcalConsumed: todayKcal,
      kcalTarget: targetKcal,
      provisional: true,
    },
    weekSummary: weekSummary(days, goal),
  };
}

function weekSummary(days: SettlementDay[], goal: Goal): string {
  if (days.length === 0) return `First week underway — the pattern starts now.`;

  const onTrack = days.filter((d) => d.kind === 'ON_TRACK').length;
  const missed = days.filter((d) => d.kind === 'MISSED').length;
  const under = days.filter((d) => d.kind === 'UNDER').length;

  if (onTrack >= days.length - 1) return `${onTrack} of ${days.length} days on target. That's the pattern to hold.`;
  if (missed + under >= Math.ceil(days.length / 2)) {
    return goal === 'BULK'
      ? `Under target more days than not this week — the gain needs the extra food.`
      : `Coming up short most days this week — let's get the floor up.`;
  }
  return `${onTrack} of ${days.length} days on target. Some ground to make up, nothing dramatic.`;
}
