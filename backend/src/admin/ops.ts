import type { PrismaClient } from '@prisma/client';
import { localDateISO, shiftDateISO } from '../engine/time.js';
import { env } from '../env.js';

/**
 * Data for the ops dashboard at /ops. Pure builders first (tested), then the
 * queries that feed them. Read-only: nothing here writes.
 */

// What one AI call costs, roughly. AiUsage stores counts only, so spend is an estimate.
export const AI_UNIT_USD: Record<string, number> = { meal_parse: 0.009, tier3_message: 0.002 };
const AI_DEFAULT_USD = 0.004;
export const AI_DAILY_BUDGET_USD = 5;

/** Days of the grid on the Now screen. */
export const GRID_DAYS = 14;
/** The scoring job should run at least this often (minutes); later than 1.4x is late. */
export const SCORE_EVERY_MIN = 15;
export const SCORE_LATE_MIN = 20;

export type Level = -1 | 0 | 1 | 2 | 3 | 4;

/** How much of the target a day reached: 0 nothing … 4 all of it. */
export function levelOf(kcal: number, target: number): 0 | 1 | 2 | 3 | 4 {
  if (kcal <= 0 || target <= 0) return 0;
  const r = kcal / target;
  if (r < 0.35) return 1;
  if (r < 0.65) return 2;
  if (r < 0.9) return 3;
  return 4;
}

/** Days in a row, ending today (or yesterday if today isn't done yet), that reached most of the target (65%+). */
export function streakOf(levels: Level[]): number {
  let i = levels.length - 1;
  if (i >= 0 && levels[i]! < 3) i -= 1; // today still in progress
  let n = 0;
  for (; i >= 0; i -= 1) {
    if (levels[i]! >= 3) n += 1;
    else break;
  }
  return n;
}

export type PushKind = 'production' | 'sandbox' | 'none' | 'setup';

export function pushStatus(tokens: { environment: string }[], onboarded: boolean): { kind: PushKind; label: string; tone: 'good' | 'warn' | 'bad' | 'off' } {
  if (tokens.some((t) => t.environment === 'production')) return { kind: 'production', label: 'Production', tone: 'good' };
  if (tokens.length > 0) return { kind: 'sandbox', label: 'Sandbox only', tone: 'warn' };
  if (!onboarded) return { kind: 'setup', label: 'Setting up', tone: 'off' };
  return { kind: 'none', label: 'No token', tone: 'bad' };
}

export type CheckInLike = {
  tier: number;
  kind: string;
  status: string;
  deliveryStatus: string;
  lastPushError?: string | null;
};

export type Outcome = 'ate' | 'answered' | 'ignored' | 'failed';

export function outcomeOf(c: CheckInLike): Outcome {
  if (c.deliveryStatus === 'FAILED') return 'failed';
  if (c.status === 'LOGGED') return 'ate';
  if (c.deliveryStatus === 'ANSWERED' || c.deliveryStatus === 'OPENED') return 'answered';
  return 'ignored';
}

/** The kinds shown on the Delivery screen. */
export function groupOf(c: Pick<CheckInLike, 'tier' | 'kind'>): { key: string; label: string; order: number } {
  if (c.tier >= 3) return { key: 'talk', label: 'Change your plan?', order: 6 };
  switch (c.kind) {
    case 'REFUEL':
      return { key: 'refuel', label: 'Refuel after training', order: 1 };
    case 'PRE_WORKOUT':
      return { key: 'pre', label: 'Before training', order: 5 };
    case 'HEADS_UP':
      return { key: 'heads', label: 'Heads-up', order: 4 };
    case 'CLOSE':
    case 'TOP_UP':
      return { key: 'close', label: 'Close the day', order: 5 };
    default:
      return c.tier >= 2 ? { key: 'firm', label: 'Meal, firm', order: 3 } : { key: 'first', label: 'Meal, first nudge', order: 2 };
  }
}

export function failureLabel(error: string | null | undefined): string {
  if (!error) return 'Unknown';
  if (error === 'no_push_token') return 'No push token';
  if (error === 'apns_not_configured') return 'Server has no push key';
  if (error.startsWith('apns_error')) return 'Server key problem';
  return 'Apple rejected it';
}

export type Step = { key: string; title: string; state: 'ok' | 'no' | 'idle'; detail: string };

/** The path of one notification, and where it breaks. */
export function buildPipeline(input: {
  tokens: { environment: string; lastSeenAt: Date }[];
  apnsConfigured: boolean;
  recent: { deliveryStatus: string; status: string; lastPushError: string | null }[];
}): { steps: Step[]; why: string | null } {
  const { tokens, apnsConfigured, recent } = input;
  const hasToken = tokens.length > 0;
  const hasProd = tokens.some((t) => t.environment === 'production');
  const last = recent[0];
  const answered = recent.some((c) => c.status === 'LOGGED' || c.deliveryStatus === 'ANSWERED' || c.deliveryStatus === 'OPENED');

  const steps: Step[] = [
    {
      key: 'token',
      title: 'The phone gave the app a token',
      state: hasToken ? 'ok' : 'no',
      detail: hasToken ? 'A push token is on file.' : 'No token on file. They haven’t allowed notifications, or the token never reached the server.',
    },
    {
      key: 'env',
      title: 'It is the right kind of token',
      state: !hasToken ? 'idle' : hasProd ? 'ok' : 'no',
      detail: !hasToken ? 'Nothing to check.' : hasProd ? 'A production token, as TestFlight and the App Store need.' : 'Only Xcode-build (sandbox) tokens. TestFlight and App Store builds need production.',
    },
    {
      key: 'key',
      title: 'The server has its push key',
      state: apnsConfigured ? 'ok' : 'no',
      detail: apnsConfigured ? 'Key, team and app ID are set.' : 'The server has no push key, so nothing is sent.',
    },
    {
      key: 'apple',
      title: 'Apple accepts the push',
      state: !last ? 'idle' : last.deliveryStatus === 'FAILED' ? 'no' : 'ok',
      detail: !last ? 'No check-in sent yet.' : last.deliveryStatus === 'FAILED' ? `The last one failed: ${failureLabel(last.lastPushError)}.` : 'The last check-in was accepted.',
    },
    {
      key: 'phone',
      title: 'The phone shows it',
      state: answered ? 'ok' : 'idle',
      detail: answered ? 'They answered one recently.' : 'Not known. Nothing answered yet.',
    },
  ];
  const broken = steps.find((s) => s.state === 'no');
  return { steps, why: broken ? broken.detail : null };
}

export function nameOf(u: { displayName: string | null; email: string | null }): string {
  const name = u.displayName?.trim();
  if (name) return name;
  const local = u.email?.split('@')[0];
  return local ? local.slice(0, 14) : 'Someone';
}

const isTestAccount = (email: string | null) => !!email && /@setpoint\.local$/i.test(email);

// ---------------------------------------------------------------------------
// Queries
// ---------------------------------------------------------------------------

export function apnsConfigured(): boolean {
  return Boolean(env.APNS_KEY_ID && env.APNS_TEAM_ID && env.APNS_PRIVATE_KEY && env.APNS_BUNDLE_ID);
}

export function estimateUsd(kind: string, calls: number): number {
  return calls * (AI_UNIT_USD[kind] ?? AI_DEFAULT_USD);
}

const DAY_MS = 86_400_000;

export async function gatherNow(prisma: PrismaClient, now: Date, sinceDayStart: Date) {
  const gridFrom = new Date(now.getTime() - (GRID_DAYS + 2) * DAY_MS);
  const weekAgo = new Date(now.getTime() - 7 * DAY_MS);

  const [users, meals, checkIns, weekCheckIns, heartbeat, aiToday, dayMeals, dayCheckIns] = await Promise.all([
    prisma.user.findMany({
      where: { onboarding: { isNot: null } },
      select: {
        id: true,
        displayName: true,
        email: true,
        timezone: true,
        createdAt: true,
        role: true,
        onboarding: { select: { dailyKcalTarget: true, completedAt: true } },
        pushTokens: { where: { kind: 'alert' }, select: { environment: true } },
      },
    }),
    prisma.meal.findMany({ where: { loggedAt: { gte: gridFrom } }, select: { userId: true, loggedAt: true, kcal: true } }),
    prisma.checkIn.findMany({
      where: { createdAt: { gte: new Date(now.getTime() - GRID_DAYS * DAY_MS) } },
      select: { userId: true, status: true, deliveryStatus: true },
    }),
    prisma.checkIn.findMany({ where: { createdAt: { gte: weekAgo } }, select: { deliveryStatus: true } }),
    prisma.schedulerHeartbeat.findUnique({ where: { job: 'score' } }),
    prisma.aiUsage.groupBy({ by: ['kind'], where: { createdAt: { gte: sinceDayStart } }, _count: { _all: true } }),
    prisma.meal.findMany({ where: { loggedAt: { gte: sinceDayStart } }, select: { loggedAt: true, kcal: true, source: true } }),
    prisma.checkIn.findMany({
      where: { createdAt: { gte: sinceDayStart } },
      select: { createdAt: true, status: true, deliveryStatus: true },
      orderBy: { createdAt: 'asc' },
    }),
  ]);

  const real = users.filter((u) => !isTestAccount(u.email));

  const mealsByUser = new Map<string, { loggedAt: Date; kcal: number }[]>();
  for (const m of meals) {
    const list = mealsByUser.get(m.userId) ?? [];
    list.push(m);
    mealsByUser.set(m.userId, list);
  }
  const ciByUser = new Map<string, { status: string; deliveryStatus: string }[]>();
  for (const c of checkIns) {
    const list = ciByUser.get(c.userId) ?? [];
    list.push(c);
    ciByUser.set(c.userId, list);
  }

  const people = real.map((u) => {
    const tz = u.timezone || 'UTC';
    const today = localDateISO(now, tz);
    const dates = Array.from({ length: GRID_DAYS }, (_, i) => shiftDateISO(today, i - (GRID_DAYS - 1)));
    const byDate = new Map<string, number>();
    const list = mealsByUser.get(u.id) ?? [];
    for (const m of list) {
      const d = localDateISO(m.loggedAt, tz);
      byDate.set(d, (byDate.get(d) ?? 0) + m.kcal);
    }
    const target = u.onboarding?.dailyKcalTarget ?? 0;
    const joined = localDateISO(u.createdAt, tz);
    const levels: Level[] = dates.map((d) => (d < joined ? -1 : levelOf(byDate.get(d) ?? 0, target)));
    const lastMeal = list.reduce<Date | null>((acc, m) => (!acc || m.loggedAt > acc ? m.loggedAt : acc), null);
    const hoursSince = lastMeal ? (now.getTime() - lastMeal.getTime()) / 3_600_000 : null;
    const push = pushStatus(u.pushTokens, Boolean(u.onboarding?.completedAt));
    const cis = ciByUser.get(u.id) ?? [];
    const answered = cis.filter((c) => c.status === 'LOGGED' || c.deliveryStatus === 'ANSWERED' || c.deliveryStatus === 'OPENED').length;
    const todayKcal = byDate.get(today) ?? 0;

    let sub: string;
    if (!u.onboarding?.completedAt) sub = 'Setting up, no meals yet';
    else if (hoursSince === null) sub = 'No meals logged yet';
    else if (hoursSince >= 48) sub = `No meal for ${Math.floor(hoursSince / 24)} days`;
    else if (hoursSince >= 24) sub = 'No meal since yesterday';
    else if (target > 0 && todayKcal >= target * 0.9) sub = 'On target today';
    else sub = `Ate ${todayKcal.toLocaleString('en-US')} of ${target.toLocaleString('en-US')} so far`;
    if (u.role !== 'USER') sub = `${u.role === 'ADMIN' ? 'Admin' : 'Trainer'} · ${sub}`;

    const quietDays = hoursSince === null ? 99 : Math.floor(hoursSince / 24);
    const needs = (push.kind === 'none' ? 3 : push.kind === 'sandbox' ? 2 : 0) + Math.min(quietDays, 5) + levels.slice(-3).filter((l) => l === 0).length;

    return {
      id: u.id,
      name: nameOf(u),
      sub,
      push: push.label,
      tone: push.tone,
      pushKind: push.kind,
      cells: levels,
      streak: streakOf(levels),
      answered: cis.length ? `${answered} of ${cis.length}` : '–',
      needs,
      activeToday: todayKcal > 0,
    };
  });
  people.sort((a, b) => b.needs - a.needs || a.name.localeCompare(b.name));

  // Loose ends, most urgent first.
  const looseEnds: { level: 'bad' | 'warn'; title: string; detail: string; link: string }[] = [];
  const unreachable = people.filter((p) => p.pushKind === 'none' || p.pushKind === 'sandbox');
  if (!apnsConfigured()) {
    looseEnds.push({ level: 'bad', title: 'The server has no push key', detail: 'Nothing can be sent. Set the APNs variables in Vercel.', link: 'machine' });
  }
  if (unreachable.length > 0) {
    const none = unreachable.filter((p) => p.pushKind === 'none').length;
    looseEnds.push({
      level: 'bad',
      title: `${unreachable.length} ${unreachable.length === 1 ? 'person' : 'people'} can’t get notifications`,
      detail: `${none} with no push token, ${unreachable.length - none} with only a sandbox token. Their check-ins fail.`,
      link: 'people',
    });
  }
  const minutesSinceRun = heartbeat ? Math.round((now.getTime() - heartbeat.lastRunAt.getTime()) / 60_000) : null;
  if (minutesSinceRun === null || minutesSinceRun > SCORE_LATE_MIN) {
    looseEnds.push({
      level: 'warn',
      title: minutesSinceRun === null ? 'Scoring has never run' : `Scoring went quiet for ${minutesSinceRun} minutes`,
      detail: `It should run every ${SCORE_EVERY_MIN} minutes. The scheduler may be throttled.`,
      link: 'machine',
    });
  }

  const weekFailed = weekCheckIns.filter((c) => c.deliveryStatus === 'FAILED').length;
  const reached = weekCheckIns.length ? Math.round(((weekCheckIns.length - weekFailed) / weekCheckIns.length) * 100) : null;
  const aiUsd = aiToday.reduce((s, r) => s + estimateUsd(r.kind, r._count._all), 0);

  return {
    now: now.toISOString(),
    looseEnds,
    numbers: {
      people: real.length,
      activeToday: people.filter((p) => p.activeToday).length,
      meals: dayMeals.length,
      photoMeals: dayMeals.filter((m) => m.source === 'PHOTO').length,
      checkInsWeek: weekCheckIns.length,
      reachedPct: reached,
      aiUsd: Math.round(aiUsd * 100) / 100,
      aiBudget: AI_DAILY_BUDGET_USD,
    },
    day: {
      start: sinceDayStart.toISOString(),
      runs: runsFrom(heartbeat?.summary).filter((t) => t >= sinceDayStart.getTime()).map((t) => new Date(t).toISOString()),
      lastRunAt: heartbeat?.lastRunAt.toISOString() ?? null,
      checkIns: dayCheckIns.map((c) => ({
        at: c.createdAt.toISOString(),
        outcome: c.deliveryStatus === 'FAILED' ? 'bad' : c.status === 'LOGGED' || c.deliveryStatus === 'ANSWERED' || c.deliveryStatus === 'OPENED' ? 'good' : 'none',
      })),
      meals: dayMeals.map((m) => ({ at: m.loggedAt.toISOString(), kcal: m.kcal })),
    },
    people: people.slice(0, 80).map(({ needs: _n, activeToday: _a, ...p }) => p),
    peopleTotal: people.length,
  };
}

/** Run times kept on the heartbeat row by `recordHeartbeat`. */
export function runsFrom(summary: unknown): number[] {
  const runs = (summary as { runs?: unknown } | null | undefined)?.runs;
  return Array.isArray(runs) ? runs.filter((r): r is number => typeof r === 'number') : [];
}

export async function gatherPerson(prisma: PrismaClient, id: string, now: Date) {
  const user = await prisma.user.findUnique({
    where: { id },
    select: {
      id: true,
      displayName: true,
      email: true,
      role: true,
      timezone: true,
      createdAt: true,
      onboarding: {
        select: {
          dailyKcalTarget: true,
          goal: true,
          targetWeightKg: true,
          paceKgPerWeek: true,
          breakfastMin: true,
          lunchMin: true,
          dinnerMin: true,
          checkInGraceMin: true,
          quietHoursStartMin: true,
          quietHoursEndMin: true,
          completedAt: true,
        },
      },
      escalationState: { select: { backedOffUntil: true, checkInsPaused: true } },
      pushTokens: { where: { kind: 'alert' }, select: { token: true, environment: true, lastSeenAt: true }, orderBy: { lastSeenAt: 'desc' } },
    },
  });
  if (!user) return null;
  const tz = user.timezone || 'UTC';
  const today = localDateISO(now, tz);
  const dates = Array.from({ length: GRID_DAYS }, (_, i) => shiftDateISO(today, i - (GRID_DAYS - 1)));
  const [meals, checkIns] = await Promise.all([
    prisma.meal.findMany({ where: { userId: id, loggedAt: { gte: new Date(now.getTime() - (GRID_DAYS + 2) * DAY_MS) } }, select: { loggedAt: true, kcal: true } }),
    prisma.checkIn.findMany({
      where: { userId: id },
      orderBy: { createdAt: 'desc' },
      take: 12,
      select: { createdAt: true, message: true, slot: true, kind: true, tier: true, status: true, deliveryStatus: true, lastPushError: true, episodeKey: true },
    }),
  ]);
  const byDate = new Map<string, number>();
  for (const m of meals) {
    const d = localDateISO(m.loggedAt, tz);
    byDate.set(d, (byDate.get(d) ?? 0) + m.kcal);
  }
  const target = user.onboarding?.dailyKcalTarget ?? 0;
  const pipeline = buildPipeline({
    tokens: user.pushTokens,
    apnsConfigured: apnsConfigured(),
    recent: checkIns.map((c) => ({ deliveryStatus: c.deliveryStatus, status: c.status, lastPushError: c.lastPushError })),
  });
  const o = user.onboarding;
  return {
    id: user.id,
    name: nameOf(user),
    role: user.role,
    joined: user.createdAt.toISOString(),
    timezone: tz,
    pipeline,
    tokens: user.pushTokens.map((t) => ({ environment: t.environment, lastSeenAt: t.lastSeenAt.toISOString(), tail: t.token.slice(-6) })),
    chart: { target, days: dates.map((d) => ({ date: d, kcal: byDate.get(d) ?? 0 })) },
    settings: o
      ? {
          mealTimes: [o.breakfastMin, o.lunchMin, o.dinnerMin],
          graceMin: o.checkInGraceMin ?? 45,
          quiet: [o.quietHoursStartMin, o.quietHoursEndMin],
          backedOffUntil: user.escalationState?.backedOffUntil?.toISOString() ?? null,
          paused: user.escalationState?.checkInsPaused ?? false,
          goal: o.goal,
          targetWeightKg: o.targetWeightKg,
          pace: o.paceKgPerWeek,
        }
      : null,
    checkIns: checkIns.map((c) => ({
      at: c.createdAt.toISOString(),
      message: c.message,
      kind: groupOf(c).label,
      delivery: c.deliveryStatus === 'FAILED' ? failureLabel(c.lastPushError) : 'Delivered',
      failed: c.deliveryStatus === 'FAILED',
      outcome: outcomeOf(c),
    })),
  };
}

export async function gatherDelivery(prisma: PrismaClient, now: Date, days: number, tzOffsetMin: number) {
  const from = new Date(now.getTime() - days * DAY_MS);
  const rows = await prisma.checkIn.findMany({
    where: { createdAt: { gte: from } },
    select: { tier: true, kind: true, status: true, deliveryStatus: true, lastPushError: true, resolvedAt: true },
  });
  const groups = new Map<string, { label: string; order: number; sent: number; ate: number; answered: number; ignored: number; failed: number }>();
  const reasons = new Map<string, number>();
  const hours = new Array<number>(24).fill(0);
  for (const r of rows) {
    const g = groupOf(r);
    const entry = groups.get(g.key) ?? { label: g.label, order: g.order, sent: 0, ate: 0, answered: 0, ignored: 0, failed: 0 };
    entry.sent += 1;
    entry[outcomeOf(r)] += 1;
    groups.set(g.key, entry);
    if (r.deliveryStatus === 'FAILED') {
      const why = failureLabel(r.lastPushError);
      reasons.set(why, (reasons.get(why) ?? 0) + 1);
    }
    if (r.resolvedAt && (r.status === 'LOGGED' || r.deliveryStatus === 'ANSWERED')) {
      const local = new Date(r.resolvedAt.getTime() - tzOffsetMin * 60_000);
      hours[local.getUTCHours()]! += 1;
    }
  }
  const total = rows.length;
  const failed = rows.filter((r) => r.deliveryStatus === 'FAILED').length;
  const answered = rows.filter((r) => outcomeOf(r) === 'ate' || outcomeOf(r) === 'answered').length;
  return {
    days,
    total,
    reached: total - failed,
    answered,
    kinds: [...groups.values()].sort((a, b) => a.order - b.order),
    reasons: [...reasons.entries()].map(([label, count]) => ({ label, count })).sort((a, b) => b.count - a.count),
    answerHours: hours,
  };
}

export type CheckState = 'ok' | 'warn' | 'off' | 'bad';

export async function gatherMachine(prisma: PrismaClient, now: Date, sinceDayStart: Date) {
  const monthStart = new Date(now.getTime() - 30 * DAY_MS);
  const [heartbeat, usage, dbMs] = await Promise.all([
    prisma.schedulerHeartbeat.findUnique({ where: { job: 'score' } }),
    prisma.aiUsage.findMany({ where: { createdAt: { gte: monthStart } }, select: { userId: true, kind: true, createdAt: true } }),
    (async () => {
      const t = Date.now();
      await prisma.$queryRaw`SELECT 1`;
      return Date.now() - t;
    })(),
  ]);

  const dayKey = (d: Date) => d.toISOString().slice(0, 10);
  const perDay = new Map<string, number>();
  const kinds = new Map<string, { calls: number; usd: number }>();
  const perUser = new Map<string, number>();
  let todayCalls = 0;
  let todayUsd = 0;
  let monthUsd = 0;
  for (const u of usage) {
    const usd = estimateUsd(u.kind, 1);
    monthUsd += usd;
    perDay.set(dayKey(u.createdAt), (perDay.get(dayKey(u.createdAt)) ?? 0) + usd);
    if (u.createdAt >= sinceDayStart) {
      todayCalls += 1;
      todayUsd += usd;
      const k = kinds.get(u.kind) ?? { calls: 0, usd: 0 };
      k.calls += 1;
      k.usd += usd;
      kinds.set(u.kind, k);
      perUser.set(u.userId, (perUser.get(u.userId) ?? 0) + usd);
    }
  }
  const days14 = Array.from({ length: 14 }, (_, i) => {
    const d = new Date(now.getTime() - (13 - i) * DAY_MS);
    return Math.round((perDay.get(dayKey(d)) ?? 0) * 100) / 100;
  });
  const top = [...perUser.entries()].sort((a, b) => b[1] - a[1])[0];
  const topUser = top
    ? await prisma.user.findUnique({ where: { id: top[0] }, select: { displayName: true, email: true } }).then((u) => (u ? { name: nameOf(u), usd: Math.round(top[1] * 100) / 100 } : null))
    : null;

  const minutesSinceRun = heartbeat ? Math.round((now.getTime() - heartbeat.lastRunAt.getTime()) / 60_000) : null;
  const sha = process.env.VERCEL_GIT_COMMIT_SHA?.slice(0, 7) ?? null;
  const checks: { key: string; title: string; detail: string; state: CheckState }[] = [
    {
      key: 'scoring',
      title: 'Scoring job',
      state: minutesSinceRun === null ? 'bad' : heartbeat?.lastOk === false ? 'bad' : minutesSinceRun > SCORE_LATE_MIN ? 'warn' : 'ok',
      detail:
        minutesSinceRun === null
          ? 'It has never run.'
          : `Should run every ${SCORE_EVERY_MIN} minutes. Last run ${minutesSinceRun} minutes ago${heartbeat?.durationMs != null ? `, ${Math.round(heartbeat.durationMs / 100) / 10} s` : ''}${heartbeat?.lastOk === false ? ', and it failed' : ''}.`,
    },
    {
      key: 'push',
      title: 'Push to Apple',
      state: apnsConfigured() ? 'ok' : 'bad',
      detail: apnsConfigured()
        ? `Key ${env.APNS_KEY_ID}, team ${env.APNS_TEAM_ID}, app ${env.APNS_BUNDLE_ID}. ${env.NODE_ENV === 'production' ? 'Production.' : 'Sandbox.'}`
        : 'Not set up. The server sends nothing.',
    },
    { key: 'db', title: 'Database', state: dbMs > 800 ? 'warn' : 'ok', detail: `Answered in ${dbMs} ms.` },
    { key: 'ai', title: 'AI', state: env.ANTHROPIC_API_KEY ? 'ok' : 'bad', detail: env.ANTHROPIC_API_KEY ? 'Key is set.' : 'No key. Meal reads and messages fail.' },
    { key: 'apple', title: 'Apple sign-in', state: env.APPLE_CLIENT_ID ? 'ok' : 'bad', detail: env.APPLE_CLIENT_ID ? `Client ID ${env.APPLE_CLIENT_ID}.` : 'No client ID set.' },
    {
      key: 'food',
      title: 'Food lookup',
      state: env.FDC_API_KEY ? 'ok' : 'warn',
      detail: env.FDC_API_KEY ? 'US food database key is set.' : 'Using the demo key, about 10 lookups an hour.',
    },
    { key: 'photos', title: 'Meal photo storage', state: env.PHOTO_BUCKET ? 'ok' : 'off', detail: env.PHOTO_BUCKET ? 'Photos are stored.' : 'Not set up. Photos are read but not kept, so a wrong read can’t be reviewed.' },
    { key: 'crash', title: 'Crash reports', state: env.SENTRY_DSN ? 'ok' : 'off', detail: env.SENTRY_DSN ? 'Sentry is connected.' : 'No Sentry address set. Errors only show in the Vercel logs.' },
    { key: 'deploy', title: 'Latest deploy', state: sha ? 'ok' : 'off', detail: sha ? `Commit ${sha}, branch ${process.env.VERCEL_GIT_COMMIT_REF ?? 'main'}.` : 'Not running on Vercel.' },
  ];

  return {
    ai: {
      todayCalls,
      todayUsd: Math.round(todayUsd * 100) / 100,
      monthUsd: Math.round(monthUsd * 100) / 100,
      budget: AI_DAILY_BUDGET_USD,
      days14,
      kinds: [...kinds.entries()].map(([kind, v]) => ({ kind, calls: v.calls, usd: Math.round(v.usd * 100) / 100 })),
      topUser,
      estimate: true,
    },
    heartbeat: {
      lastRunAt: heartbeat?.lastRunAt.toISOString() ?? null,
      lastOk: heartbeat?.lastOk ?? null,
      durationMs: heartbeat?.durationMs ?? null,
      runs: runsFrom(heartbeat?.summary).map((t) => new Date(t).toISOString()),
    },
    checks,
  };
}
