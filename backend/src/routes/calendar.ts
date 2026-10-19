import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { requireAuth, type AuthedRequest } from '../auth/index.js';
import { getPrisma } from '../db/client.js';
import { requireEntitlement } from '../subscription/requireEntitlement.js';
import {
  localDateISO,
  localDayRange,
  localWeekday,
  msSinceLocalMidnight,
  shiftDateISO,
  startOfLocalDay,
  weekdayOfLocalDate,
} from '../engine/time.js';
import { prefsFromProfile, toMinuteBlocks } from '../engine/calendarBusy.js';
import { buildCalendarDay, buildCalendarWeek, mondayOffset, type CalendarDayInput } from '../engine/calendarWeek.js';
import { mealTimesOn } from '../engine/mealSchedule.js';
import { clearBusy, replaceBusyWindow } from '../calendar/replaceBusy.js';

const iso = z.string().min(10);
const localDate = z.string().regex(/^\d{4}-\d{2}-\d{2}$/);

/** Today plus the next week, with an hour of slack for DST and clock drift. */
const MAX_WINDOW_MS = (9 * 24 + 1) * 3_600_000;

const busyBody = z.object({
  from: iso,
  to: iso,
  blocks: z
    .array(z.object({ start: iso, end: iso, allDay: z.boolean().optional() }))
    .max(500),
});

const keepBody = z.object({
  date: localDate,
  slot: z.enum(['breakfast', 'lunch', 'dinner']),
  keep: z.boolean(),
});

type BusyRow = { start: Date; end: Date; allDay: boolean };

function parseWindow(app: FastifyInstance, body: z.infer<typeof busyBody>) {
  const from = new Date(body.from);
  const to = new Date(body.to);
  const span = to.getTime() - from.getTime();
  if (!(span > 0) || span > MAX_WINDOW_MS) {
    throw app.httpErrors.badRequest('busy window must be between 0 and 9 days');
  }
  const blocks: BusyRow[] = body.blocks.map((b) => ({
    start: new Date(b.start),
    end: new Date(b.end),
    allDay: b.allDay ?? false,
  }));
  return { from, to, blocks };
}

export async function calendarRoutes(app: FastifyInstance): Promise<void> {
  app.addHook('preHandler', requireAuth(app));

  app.put('/busy', async (req) => {
    const { from, to, blocks } = parseWindow(app, busyBody.parse(req.body));
    const userId = (req as AuthedRequest).userId;
    await requireEntitlement(app, userId);
    const stored = await replaceBusyWindow(getPrisma(), userId, from, to, blocks);
    return { stored };
  });

  app.get('/', async (req) => {
    const prisma = getPrisma();
    const userId = (req as AuthedRequest).userId;
    const user = await prisma.user.findUnique({
      where: { id: userId },
      include: { onboarding: true },
    });
    if (!user?.onboarding) throw app.httpErrors.conflict('onboarding not complete');
    const p = user.onboarding;
    const now = new Date();
    const weekAgo = new Date(now.getTime() - 7 * 86_400_000);
    const weekEnd = new Date(now.getTime() + 7 * 86_400_000);
    const [moved, blocks] = await Promise.all([
      prisma.checkIn.count({
        where: { userId, movedFromMin: { not: null }, createdAt: { gte: weekAgo } },
      }),
      prisma.calendarBusyBlock.findMany({
        where: { userId, start: { lt: weekEnd }, end: { gt: weekAgo } },
        select: { start: true, end: true, allDay: true },
        orderBy: { start: 'asc' },
      }),
    ]);
    const week: { date: string; startMin: number; endMin: number }[] = [];
    for (let i = 0; i < 7; i += 1) {
      const day = new Date(now.getTime() + i * 86_400_000);
      const dayStart = startOfLocalDay(day, user.timezone);
      const date = localDateISO(dayStart, user.timezone);
      for (const block of toMinuteBlocks(blocks, dayStart, user.timezone)) {
        week.push({ date, startMin: block.startMin, endMin: block.endMin });
      }
    }
    return {
      enabled: p.calendarEnabled,
      leadMin: p.calendarLeadMin,
      minBlockMin: p.calendarMinBlockMin,
      workdaysOnly: p.calendarWorkdaysOnly,
      includeAllDay: p.calendarIncludeAllDay,
      countFree: p.calendarCountFree,
      mealsMovedThisWeek: moved,
      week,
    };
  });

  /** The week screen: Mon–Sun busy stretches, where each meal lands, and the next move ahead. */
  app.get('/week', async (req) => {
    const prisma = getPrisma();
    const userId = (req as AuthedRequest).userId;
    const user = await prisma.user.findUnique({ where: { id: userId }, include: { onboarding: true } });
    if (!user?.onboarding) throw app.httpErrors.conflict('onboarding not complete');
    const profile = user.onboarding;
    const tz = user.timezone;
    const now = new Date();
    const today = localDateISO(now, tz);
    const monday = shiftDateISO(today, mondayOffset(localWeekday(now, tz)));
    const weekDates = Array.from({ length: 7 }, (_, i) => shiftDateISO(monday, i));
    // On Sunday the grid is nearly over — look a week ahead for "Tomorrow".
    const lastDate = [weekDates[6]!, shiftDateISO(today, 7)].sort().at(-1)!;
    const allDates: string[] = [];
    for (let d = monday; d <= lastDate; d = shiftDateISO(d, 1)) allDates.push(d);
    const rangeStart = localDayRange(monday, tz).start;
    const rangeEnd = localDayRange(lastDate, tz).end;

    const [busyRows, meals, keeps] = await Promise.all([
      prisma.calendarBusyBlock.findMany({
        where: { userId, start: { lt: rangeEnd }, end: { gt: rangeStart } },
        select: { start: true, end: true, allDay: true },
      }),
      prisma.meal.findMany({
        where: { userId, loggedAt: { gte: rangeStart, lt: rangeEnd } },
        select: { loggedAt: true, kcal: true },
      }),
      prisma.calendarKeep.findMany({
        where: { userId, localDate: { gte: monday, lte: lastDate } },
        select: { localDate: true, slot: true },
      }),
    ]);

    const inputs: CalendarDayInput[] = allDates.map((date) => {
      const { start, end } = localDayRange(date, tz);
      const weekday = weekdayOfLocalDate(date);
      return {
        date,
        weekday,
        times: mealTimesOn(profile, weekday),
        blocks: toMinuteBlocks(busyRows, start, tz),
        meals: meals
          .filter((m) => m.loggedAt >= start && m.loggedAt < end)
          .map((m) => ({ minuteOfDay: Math.floor(msSinceLocalMidnight(m.loggedAt, tz) / 60_000), kcal: m.kcal })),
        kept: keeps.filter((k) => k.localDate === date).map((k) => k.slot),
      };
    });

    const prefs = prefsFromProfile(profile);
    const week = buildCalendarWeek({
      week: inputs.slice(0, 7),
      lookahead: inputs.slice(7),
      today,
      nowMin: Math.floor(msSinceLocalMidnight(now, tz) / 60_000),
      prefs,
    });
    return {
      enabled: prefs.enabled,
      leadMin: prefs.leadMin,
      minBlockMin: prefs.minBlockMin,
      workdaysOnly: prefs.workdaysOnly,
      includeAllDay: prefs.includeAllDay,
      countFree: profile.calendarCountFree,
      today,
      ...week,
    };
  });

  /** "Keep lunch at 13:00" — or undo it. */
  app.post('/keep', async (req) => {
    const body = keepBody.parse(req.body);
    const prisma = getPrisma();
    const userId = (req as AuthedRequest).userId;
    const key = { userId, localDate: body.date, slot: body.slot };
    if (body.keep) {
      await prisma.calendarKeep.upsert({ where: { userId_localDate_slot: key }, create: key, update: {} });
    } else {
      await prisma.calendarKeep.deleteMany({ where: key });
    }
    return { date: body.date, slot: body.slot, kept: body.keep };
  });

  /**
   * Before connecting: which meals the picked calendars would move over the
   * next seven days. Nothing is stored.
   */
  app.post('/preview', async (req) => {
    const { blocks } = parseWindow(app, busyBody.parse(req.body));
    const prisma = getPrisma();
    const userId = (req as AuthedRequest).userId;
    const user = await prisma.user.findUnique({ where: { id: userId }, include: { onboarding: true } });
    if (!user?.onboarding) throw app.httpErrors.conflict('onboarding not complete');
    const profile = user.onboarding;
    const tz = user.timezone;
    const now = new Date();
    const today = localDateISO(now, tz);
    const prefs = { ...prefsFromProfile(profile), enabled: true };
    const moved = Array.from({ length: 7 }, (_, i) => shiftDateISO(today, i)).flatMap((date) => {
      const weekday = weekdayOfLocalDate(date);
      const day = buildCalendarDay(
        {
          date,
          weekday,
          times: mealTimesOn(profile, weekday),
          blocks: toMinuteBlocks(blocks, localDayRange(date, tz).start, tz),
          meals: [],
          kept: [],
        },
        { today: date, nowMin: 0, prefs },
      );
      return day.meals
        .filter((m) => m.moved)
        .map((m) => ({ date, weekday, slot: m.slot, usualMin: m.usualMin, atMin: m.atMin }));
    });
    return { movedCount: moved.length, moved };
  });

  app.delete('/', async (req) => {
    const prisma = getPrisma();
    const userId = (req as AuthedRequest).userId;
    await prisma.onboardingProfile.updateMany({
      where: { userId },
      data: { calendarEnabled: false },
    });
    await clearBusy(prisma, userId);
    await prisma.calendarKeep.deleteMany({ where: { userId } });
    return { enabled: false };
  });
}
