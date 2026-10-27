import type { PrismaClient } from '@prisma/client';
import { summarizeEvents, type EventRow } from '../analytics/events.js';

/**
 * The numbers behind the dashboard's Usage tab and the daily/weekly digest:
 * who is active, who comes back, and which features people actually use.
 * Everything is derived from the analytics events and the users' sign-up dates.
 */

const DAY_MS = 86_400_000;
const MAX_ROWS = 200_000;
export const RETENTION_WEEKS = 8;

/** Events that don't mean the person did anything (the server writes them on a schedule). */
const PASSIVE_EVENTS = new Set(['day_settled', 'request_failed']);

/** Feature → the events that count as using it. */
export const FEATURES: Record<string, readonly string[]> = {
  'Log a meal': ['meal_logged'],
  'Check-in answer': ['check_in_answered'],
  'Weigh-in': ['weigh_in_logged'],
  'Fix a meal': ['meal_fixed'],
  'Order nearby': ['order_nearby_opened', 'wolt_opened'],
  'Nutrition assistant': ['expert_open', 'expert_send'],
  Train: ['workout_planned', 'workout_completed', 'workout_skipped'],
  Subscription: ['subscription_verified'],
};

export type ActiveRow = Pick<EventRow, 'userId' | 'name' | 'occurredAt'>;
export type SignupRow = { id: string; createdAt: Date };

export function dayKey(d: Date): string {
  return d.toISOString().slice(0, 10);
}

function startOfWeek(d: Date): Date {
  const day = new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate()));
  const dow = (day.getUTCDay() + 6) % 7; // Monday = 0
  return new Date(day.getTime() - dow * DAY_MS);
}

/** Per person, the set of days they did something. */
export function activeDays(rows: ActiveRow[]): Map<string, Set<string>> {
  const out = new Map<string, Set<string>>();
  for (const row of rows) {
    if (!row.userId || PASSIVE_EVENTS.has(row.name)) continue;
    const days = out.get(row.userId) ?? new Set<string>();
    days.add(dayKey(row.occurredAt));
    out.set(row.userId, days);
  }
  return out;
}

function peopleActiveBetween(days: Map<string, Set<string>>, from: Date, to: Date): number {
  const a = dayKey(from);
  const b = dayKey(to);
  let n = 0;
  for (const set of days.values()) {
    for (const d of set) {
      if (d >= a && d <= b) {
        n += 1;
        break;
      }
    }
  }
  return n;
}

/** DAU/WAU/MAU as of `now`, plus how many people were active each day of the range. */
export function activity(rows: ActiveRow[], now: Date, rangeDays: number) {
  const days = activeDays(rows);
  const dau = peopleActiveBetween(days, now, now);
  const wau = peopleActiveBetween(days, new Date(now.getTime() - 6 * DAY_MS), now);
  const mau = peopleActiveBetween(days, new Date(now.getTime() - 29 * DAY_MS), now);
  const series: Array<{ date: string; activeUsers: number }> = [];
  for (let i = rangeDays - 1; i >= 0; i -= 1) {
    const date = dayKey(new Date(now.getTime() - i * DAY_MS));
    let n = 0;
    for (const set of days.values()) if (set.has(date)) n += 1;
    series.push({ date, activeUsers: n });
  }
  return { dau, wau, mau, stickiness: mau ? dau / mau : null, series };
}

/**
 * Sign-up weeks down the side, weeks since sign-up across: the share of each
 * week's sign-ups who did something in week N. Plus the usual D1/D7/D30 returns.
 */
export function retention(signups: SignupRow[], days: Map<string, Set<string>>, now: Date) {
  const weeks = new Map<string, SignupRow[]>();
  for (const s of signups) {
    const key = dayKey(startOfWeek(s.createdAt));
    weeks.set(key, [...(weeks.get(key) ?? []), s]);
  }
  const cohorts = [...weeks]
    .sort(([a], [b]) => a.localeCompare(b))
    .map(([weekStart, people]) => {
      const start = new Date(`${weekStart}T00:00:00Z`);
      const shares: Array<number | null> = [];
      for (let w = 0; w <= RETENTION_WEEKS; w += 1) {
        const from = new Date(start.getTime() + w * 7 * DAY_MS);
        const to = new Date(from.getTime() + 6 * DAY_MS);
        if (from.getTime() > now.getTime()) {
          shares.push(null);
          continue;
        }
        const a = dayKey(from);
        const b = dayKey(to);
        const back = people.filter((p) => [...(days.get(p.id) ?? [])].some((d) => d >= a && d <= b)).length;
        shares.push(people.length ? back / people.length : null);
      }
      return { weekStart, size: people.length, weeks: shares };
    });

  const returned = (offset: number) => {
    let eligible = 0;
    let back = 0;
    for (const s of signups) {
      const target = new Date(s.createdAt.getTime() + offset * DAY_MS);
      if (target.getTime() > now.getTime()) continue;
      eligible += 1;
      if (days.get(s.id)?.has(dayKey(target))) back += 1;
    }
    return { eligible, returned: back, rate: eligible ? back / eligible : null };
  };

  return { cohorts, d1: returned(1), d7: returned(7), d30: returned(30) };
}

/** Per feature: who has ever used it, who used it this week, who uses it often. */
export function adoption(rows: ActiveRow[], now: Date, totalPeople: number) {
  const weekAgo = now.getTime() - 7 * DAY_MS;
  return Object.entries(FEATURES).map(([feature, names]) => {
    const uses = new Map<string, { n: number; recent: boolean }>();
    for (const row of rows) {
      if (!row.userId || !names.includes(row.name)) continue;
      const u = uses.get(row.userId) ?? { n: 0, recent: false };
      u.n += 1;
      if (row.occurredAt.getTime() >= weekAgo) u.recent = true;
      uses.set(row.userId, u);
    }
    const people = [...uses.values()];
    return {
      feature,
      everUsed: people.length,
      usedThisWeek: people.filter((p) => p.recent).length,
      usedThreeTimes: people.filter((p) => p.n >= 3).length,
      share: totalPeople ? people.length / totalPeople : null,
    };
  });
}

export type Usage = Awaited<ReturnType<typeof gatherUsage>>;

export async function gatherUsage(prisma: PrismaClient, opts: { days: number; cohort?: string; now?: Date }) {
  const now = opts.now ?? new Date();
  const from = new Date(now.getTime() - opts.days * DAY_MS);
  const userWhere = opts.cohort ? { cohort: opts.cohort } : {};
  const people = await prisma.user.findMany({ where: userWhere, select: { id: true, createdAt: true } });
  const ids = people.map((p) => p.id);
  const rows = await prisma.analyticsEvent.findMany({
    where: {
      occurredAt: { gte: from, lte: now },
      ...(opts.cohort ? { userId: { in: ids } } : {}),
    },
    select: { userId: true, name: true, props: true, occurredAt: true },
    orderBy: { occurredAt: 'asc' },
    take: MAX_ROWS,
  });
  // Retention needs history past the range: sign-ups reach back RETENTION_WEEKS.
  const longFrom = new Date(now.getTime() - (RETENTION_WEEKS + 1) * 7 * DAY_MS);
  const longRows =
    longFrom.getTime() < from.getTime()
      ? await prisma.analyticsEvent.findMany({
          where: { occurredAt: { gte: longFrom, lte: now }, ...(opts.cohort ? { userId: { in: ids } } : {}) },
          select: { userId: true, name: true, occurredAt: true },
          take: MAX_ROWS,
        })
      : rows;
  const recentSignups = people.filter((p) => p.createdAt.getTime() >= longFrom.getTime());

  return {
    range: { from: from.toISOString(), to: now.toISOString(), days: opts.days },
    cohort: opts.cohort ?? null,
    people: people.length,
    truncated: rows.length === MAX_ROWS,
    summary: summarizeEvents(rows),
    activity: activity(longRows, now, Math.min(opts.days, 60)),
    retention: retention(recentSignups, activeDays(longRows), now),
    adoption: adoption(longRows, now, people.length),
  };
}
