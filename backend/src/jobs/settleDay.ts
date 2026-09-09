import type { PrismaClient } from '@prisma/client';
import { dateOnly, localDateISO, shiftDateISO, startOfLocalDay, type Goal } from '../engine/index.js';
import { classifyDay } from '../dashboard/classify.js';
import type { ManagerVoice } from '../managerVoice/types.js';

export type SettleDayDeps = {
  prisma: PrismaClient;
  voice: ManagerVoice;
  now?: Date;
};

export type SettleDaySummary = {
  ranAt: string;
  usersEvaluated: number;
  outcomesWritten: number;
  errors: number;
  byKind: Record<string, number>;
};

/**
 * Daily job: writes the previous local day's `DayOutcome` for every onboarded
 * user (plan §5.7). Idempotent — re-running upserts the same row.
 */
export async function runSettleDayJob(deps: SettleDayDeps): Promise<SettleDaySummary> {
  const now = deps.now ?? new Date();
  const summary: SettleDaySummary = {
    ranAt: now.toISOString(),
    usersEvaluated: 0,
    outcomesWritten: 0,
    errors: 0,
    byKind: {},
  };

  const users = await deps.prisma.user.findMany({
    where: { onboarding: { is: { completedAt: { not: null } } } },
    include: { onboarding: true },
  });
  summary.usersEvaluated = users.length;

  for (const user of users) {
    if (!user.onboarding) continue;
    try {
      const todayStart = startOfLocalDay(now, user.timezone);
      // 1s before local midnight lands in the previous day; DST-correct.
      const yesterdayStart = startOfLocalDay(new Date(todayStart.getTime() - 1000), user.timezone);
      const yesterdayISO = shiftDateISO(localDateISO(now, user.timezone), -1);

      const meals = await deps.prisma.meal.findMany({
        where: { userId: user.id, loggedAt: { gte: yesterdayStart, lt: todayStart } },
        select: { kcal: true },
      });

      const kcalConsumed = meals.reduce((acc, m) => acc + m.kcal, 0);
      const kcalTarget = user.onboarding.dailyKcalTarget;
      const kind = classifyDay(kcalConsumed, kcalTarget);

      const summaryLine = await deps.voice.daySummary({
        goal: user.onboarding.goal as Goal,
        kind,
        kcalConsumed,
        kcalTarget,
      });

      await deps.prisma.dayOutcome.upsert({
        where: { userId_date: { userId: user.id, date: dateOnly(yesterdayISO) } },
        create: { userId: user.id, date: dateOnly(yesterdayISO), kind, kcalConsumed, kcalTarget, summaryLine },
        update: { kind, kcalConsumed, kcalTarget, summaryLine },
      });

      summary.outcomesWritten += 1;
      summary.byKind[kind] = (summary.byKind[kind] ?? 0) + 1;
    } catch (err) {
      summary.errors += 1;
      console.error(`settleDay: user ${user.id} failed`, err);
    }
  }

  return summary;
}
