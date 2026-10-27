import type { PrismaClient } from '@prisma/client';
import { summarizeEvents } from '../analytics/events.js';
import { activeDays } from './usage.js';

const DAY_MS = 86_400_000;

export type DigestPeriod = 'daily' | 'weekly';

type Counts = {
  signedUp: number;
  activeUsers: number;
  mealsLogged: number;
  checkInsAnswered: number;
  mealFailRate: number | null;
  crashes: number;
  serverErrors: number;
};

export type Digest = {
  period: DigestPeriod;
  generatedAt: string;
  from: string;
  to: string;
  current: Counts;
  previous: Counts;
  /** Plain text, ready to drop into a message. */
  text: string;
};

async function countsFor(prisma: PrismaClient, from: Date, to: Date): Promise<Counts> {
  const rows = await prisma.analyticsEvent.findMany({
    where: { occurredAt: { gte: from, lt: to } },
    select: { userId: true, name: true, props: true, occurredAt: true },
    take: 200_000,
  });
  const s = summarizeEvents(rows);
  return {
    signedUp: s.totals.signed_up?.events ?? 0,
    activeUsers: activeDays(rows).size,
    mealsLogged: s.meals.logged,
    checkInsAnswered: s.totals.check_in_answered?.events ?? 0,
    mealFailRate: s.meals.failRate,
    crashes: s.problems.crashes,
    serverErrors: s.problems.serverErrors,
  };
}

function change(now: number, before: number): string {
  if (now === before) return '=';
  if (!before) return `+${now}`;
  const pct = Math.round(((now - before) / before) * 100);
  return `${pct > 0 ? '+' : ''}${pct}%`;
}

const pct = (v: number | null) => (v === null ? '–' : `${Math.round(v * 100)}%`);

export function digestText(period: DigestPeriod, current: Counts, previous: Counts): string {
  const vs = period === 'daily' ? 'vs the day before' : 'vs the week before';
  return [
    `SetPoint ${period} digest (${vs})`,
    `New sign-ups: ${current.signedUp} (${change(current.signedUp, previous.signedUp)})`,
    `Active people: ${current.activeUsers} (${change(current.activeUsers, previous.activeUsers)})`,
    `Meals logged: ${current.mealsLogged} (${change(current.mealsLogged, previous.mealsLogged)})`,
    `Check-ins answered: ${current.checkInsAnswered} (${change(current.checkInsAnswered, previous.checkInsAnswered)})`,
    `Meal log failures: ${pct(current.mealFailRate)}`,
    `Crashes: ${current.crashes} · server errors: ${current.serverErrors}`,
  ].join('\n');
}

/** The last full day, or the last seven days, against the period before it. */
export async function buildDigest(prisma: PrismaClient, period: DigestPeriod, now: Date = new Date()): Promise<Digest> {
  const span = (period === 'daily' ? 1 : 7) * DAY_MS;
  const to = new Date(now);
  const from = new Date(to.getTime() - span);
  const before = new Date(from.getTime() - span);
  const [current, previous] = await Promise.all([countsFor(prisma, from, to), countsFor(prisma, before, from)]);
  return {
    period,
    generatedAt: now.toISOString(),
    from: from.toISOString(),
    to: to.toISOString(),
    current,
    previous,
    text: digestText(period, current, previous),
  };
}

/** Keeps the latest of each digest in AppConfig, so the dashboard can show it. */
export async function storeDigest(prisma: PrismaClient, digest: Digest): Promise<void> {
  const key = `digest:${digest.period}`;
  const value = JSON.parse(JSON.stringify(digest));
  await prisma.appConfig.upsert({ where: { key }, create: { key, value }, update: { value } });
}
