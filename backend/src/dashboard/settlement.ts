import type { PrismaClient } from '@prisma/client';
import { localDateISO, shiftDateISO, startOfLocalDay, type Goal } from '../engine/index.js';
import { computeWeightProgress, type PaceStatus } from '../weight/progress.js';
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

export type WeightGoalView = {
  goal: Goal;
  startWeightKg: number | null;
  targetWeightKg: number | null;
  currentWeightKg: number | null;
  changedKg: number | null;
  remainingKg: number | null;
  totalKg: number | null;
  fractionComplete: number | null;
  status: PaceStatus;
  etaWeeks: number | null;
  lastWeighInAt: string | null;
  /** No weigh-in in the last week — prompt for one. */
  needsWeighIn: boolean;
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
  /** Null when the user has no weight goal (MAINTAIN or none set). */
  weightGoal: WeightGoalView | null;
};

const WINDOW_DAYS = 7;

export async function buildSettlement(deps: SettlementDeps, userId: string): Promise<SettlementView> {
  const now = deps.now ?? new Date();
  const { prisma } = deps;

  const user = await prisma.user.findUnique({
    where: { id: userId },
    include: {
      onboarding: true,
      weightEntries: { orderBy: { measuredAt: 'desc' }, take: 1 },
    },
  });
  if (!user?.onboarding) throw new OnboardingIncompleteError('onboarding not complete');

  const profile = user.onboarding;
  const goal = profile.goal as Goal;
  const targetKcal = profile.dailyKcalTarget;

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
    weightGoal: buildWeightGoal(profile, user.weightEntries[0] ?? null, now),
  };
}

const WEIGH_IN_STALE_MS = 7 * 24 * 3_600_000;

function buildWeightGoal(
  profile: {
    goal: string;
    startWeightKg: number | null;
    targetWeightKg: number | null;
    paceKgPerWeek: number;
    goalStartedAt: Date | null;
    weightKg: number | null;
  },
  latest: { weightKg: number; measuredAt: Date } | null,
  now: Date,
): WeightGoalView | null {
  const goal = profile.goal as Goal;
  if (goal === 'MAINTAIN') return null;
  if (profile.targetWeightKg == null) return null;

  const currentWeightKg = latest?.weightKg ?? profile.startWeightKg ?? profile.weightKg ?? null;
  const progress = computeWeightProgress({
    goal,
    startWeightKg: profile.startWeightKg,
    targetWeightKg: profile.targetWeightKg,
    currentWeightKg,
    paceKgPerWeek: profile.paceKgPerWeek,
    goalStartedAt: profile.goalStartedAt,
    now,
  });

  const lastWeighInAt = latest?.measuredAt ?? null;
  const needsWeighIn =
    lastWeighInAt == null || now.getTime() - lastWeighInAt.getTime() > WEIGH_IN_STALE_MS;

  return {
    goal,
    startWeightKg: profile.startWeightKg,
    targetWeightKg: profile.targetWeightKg,
    currentWeightKg,
    changedKg: progress?.changedKg ?? null,
    remainingKg: progress?.remainingKg ?? null,
    totalKg: progress?.totalKg ?? null,
    fractionComplete: progress?.fractionComplete ?? null,
    status: progress?.status ?? 'unknown',
    etaWeeks: progress?.etaWeeks ?? null,
    lastWeighInAt: lastWeighInAt?.toISOString() ?? null,
    needsWeighIn,
  };
}

function weekSummary(days: SettlementDay[], goal: Goal): string {
  if (days.length === 0) return `First week underway.`;

  const onTrack = days.filter((d) => d.kind === 'ON_TRACK').length;
  const missed = days.filter((d) => d.kind === 'MISSED').length;
  const under = days.filter((d) => d.kind === 'UNDER').length;

  if (onTrack >= days.length - 1) return `${onTrack} of ${days.length} days on target.`;
  if (missed + under >= Math.ceil(days.length / 2)) {
    if (goal === 'BULK') return `Mostly under target. Eat more for your gain goal.`;
    if (goal === 'MAINTAIN') return `Mostly under maintenance.`;
    return `Mostly under target.`;
  }
  return `${onTrack} of ${days.length} days on target.`;
}
