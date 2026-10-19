import type { Prisma, PrismaClient } from '@prisma/client';

/**
 * Product analytics in our own database: what someone did and which screens they
 * opened. Props are a few short codes (a meal's source, a check-in answer, a
 * screen name). What people ate and weighed isn't copied here — the dashboard
 * reads it from the meals and weigh-ins themselves (see nutrition.ts).
 * Recording never fails the request it rides on.
 */
export const EVENTS = [
  'signed_up',
  'invite_redeemed',
  'onboarding_completed',
  'meal_logged',
  'meal_fixed',
  'check_in_answered',
  'day_settled',
  'order_nearby_opened',
  'wolt_opened',
  'app_opened',
  'screen_viewed',
] as const;

export type EventName = (typeof EVENTS)[number];

/** The only events the app may send itself; the rest are recorded where they happen. */
export const CLIENT_EVENTS = ['app_opened', 'wolt_opened', 'screen_viewed'] as const satisfies readonly EventName[];

export type EventProps = Record<string, string | number | boolean>;

const MAX_PROPS = 8;
const MAX_VALUE_LENGTH = 40;

/** Keeps props to a few short codes — no free text slips into analytics. */
export function cleanProps(raw: unknown): EventProps | undefined {
  if (!raw || typeof raw !== 'object' || Array.isArray(raw)) return undefined;
  const out: EventProps = {};
  for (const [key, value] of Object.entries(raw as Record<string, unknown>)) {
    if (Object.keys(out).length >= MAX_PROPS) break;
    if (!/^[a-zA-Z][a-zA-Z0-9_]{0,31}$/.test(key)) continue;
    if (typeof value === 'number' && Number.isFinite(value)) out[key] = value;
    else if (typeof value === 'boolean') out[key] = value;
    else if (typeof value === 'string' && value.length <= MAX_VALUE_LENGTH && /^[\w.:-]*$/.test(value)) out[key] = value;
  }
  return Object.keys(out).length ? out : undefined;
}

export async function track(
  prisma: PrismaClient,
  userId: string | null,
  name: EventName,
  props?: EventProps,
  opts: { dedupeKey?: string; at?: Date } = {},
): Promise<void> {
  try {
    await prisma.analyticsEvent.createMany({
      data: [
        {
          userId,
          name,
          props: (cleanProps(props) ?? undefined) as Prisma.InputJsonValue | undefined,
          dedupeKey: opts.dedupeKey ?? null,
          occurredAt: opts.at ?? new Date(),
        },
      ],
      skipDuplicates: true,
    });
  } catch (err) {
    console.warn(`analytics: ${name} not recorded`, err);
  }
}

export type EventRow = { userId: string | null; name: string; props: unknown; occurredAt: Date };

const FULL_DAY_KINDS = new Set(['ON_TRACK', 'OVER']);

/**
 * The numbers for a range of events: totals per event, people per day, and the
 * pilot funnel — signed up → set up → logged a meal → answered a check-in → had
 * a fully eaten day.
 */
export function summarizeEvents(rows: EventRow[]) {
  const byName = new Map<string, { events: number; users: Set<string> }>();
  const byDay = new Map<string, { users: Set<string>; meals: number; checkIns: number }>();
  const byScreen = new Map<string, { views: number; users: Set<string> }>();
  const usersWith = (name: string) => byName.get(name)?.users ?? new Set<string>();
  let settledDays = 0;
  let fullDays = 0;
  const fullDayUsers = new Set<string>();

  for (const row of rows) {
    const entry = byName.get(row.name) ?? { events: 0, users: new Set<string>() };
    entry.events += 1;
    if (row.userId) entry.users.add(row.userId);
    byName.set(row.name, entry);

    const day = row.occurredAt.toISOString().slice(0, 10);
    const d = byDay.get(day) ?? { users: new Set<string>(), meals: 0, checkIns: 0 };
    if (row.userId && row.name !== 'day_settled') d.users.add(row.userId);
    if (row.name === 'meal_logged') d.meals += 1;
    if (row.name === 'check_in_answered') d.checkIns += 1;
    byDay.set(day, d);

    if (row.name === 'screen_viewed') {
      const screen = (row.props as { screen?: unknown } | null)?.screen;
      if (typeof screen === 'string') {
        const s = byScreen.get(screen) ?? { views: 0, users: new Set<string>() };
        s.views += 1;
        if (row.userId) s.users.add(row.userId);
        byScreen.set(screen, s);
      }
    }

    if (row.name === 'day_settled') {
      settledDays += 1;
      const kind = (row.props as { kind?: unknown } | null)?.kind;
      if (typeof kind === 'string' && FULL_DAY_KINDS.has(kind)) {
        fullDays += 1;
        if (row.userId) fullDayUsers.add(row.userId);
      }
    }
  }

  const signedUp = usersWith('signed_up');
  const inFunnel = (set: Set<string>) => [...set].filter((u) => signedUp.has(u)).length;

  return {
    totals: Object.fromEntries([...byName].map(([name, v]) => [name, { events: v.events, users: v.users.size }])),
    daily: [...byDay]
      .sort(([a], [b]) => a.localeCompare(b))
      .map(([date, v]) => ({ date, activeUsers: v.users.size, mealsLogged: v.meals, checkInsAnswered: v.checkIns })),
    funnel: {
      signedUp: signedUp.size,
      onboarded: inFunnel(usersWith('onboarding_completed')),
      loggedAMeal: inFunnel(usersWith('meal_logged')),
      answeredACheckIn: inFunnel(usersWith('check_in_answered')),
      hadAFullDay: inFunnel(fullDayUsers),
    },
    days: { settled: settledDays, fullyEaten: fullDays, fullyEatenRate: settledDays ? fullDays / settledDays : null },
    screens: [...byScreen]
      .map(([screen, v]) => ({ screen, views: v.views, users: v.users.size }))
      .sort((a, b) => b.views - a.views),
  };
}
