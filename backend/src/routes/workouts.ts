import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { requireAuth, type AuthedRequest } from '../auth/index.js';
import { getPrisma } from '../db/client.js';
import { requireEntitlement } from '../subscription/requireEntitlement.js';
import { localDateISO, localDayRange, msSinceLocalMidnight, shiftDateISO, startOfLocalDay } from '../engine/time.js';
import { applyTrainingTarget, effectiveWorkouts, REFUEL_WINDOW_MIN, trainingBump } from '../engine/training.js';
import { asTrainingWorkout } from '../training/day.js';
import { replaceWorkouts } from '../training/replaceWorkouts.js';
import { canEdit, followingStarts, PLAN_HORIZON_DAYS, startProblem } from '../training/schedule.js';
import { excludedTokensFrom, loadStapleFoods } from '../solver/meals.js';
import { pickSnackBefore } from '../training/snack.js';
import { refuelMealFor, refuelStatus, todaySteps } from '../training/status.js';

const kind = z.enum(['STRENGTH', 'CARDIO', 'MIXED']);
const source = z.enum(['HEALTHKIT', 'PLANNED']);

const workoutBody = z.object({
  source,
  kind,
  start: z.string().min(10),
  durationMin: z.number().int().min(5).max(360),
  activeKcal: z.number().int().min(0).max(4000).nullable().optional(),
  clientId: z.string().min(1).max(80).nullable().optional(),
});

const putBody = z.object({
  workouts: z.array(workoutBody).max(80),
});

const plannedBody = z
  .object({
    kind,
    durationMin: z.number().int().min(5).max(360),
    /** One session, the older shape. */
    start: z.string().min(10).optional(),
    /** One or more sessions with ids the phone made, so it can show them before the reply. */
    sessions: z
      .array(z.object({ clientId: z.string().min(1).max(80), start: z.string().min(10) }))
      .min(1)
      .max(60)
      .optional(),
    /** Set when the sessions are one weekly repeat. */
    seriesId: z.string().min(1).max(80).nullable().optional(),
  })
  .refine((b) => b.start || b.sessions, { message: 'start or sessions required' });

const editBody = z.object({
  kind: kind.optional(),
  start: z.string().min(10).optional(),
  durationMin: z.number().int().min(5).max(360).optional(),
  /** "following": this session and every later one in its weekly repeat. */
  scope: z.enum(['one', 'following']).default('one'),
});

const scopeQuery = z.object({ scope: z.enum(['one', 'following']).default('one') });

export async function workoutRoutes(app: FastifyInstance): Promise<void> {
  app.addHook('preHandler', requireAuth(app));

  app.put('/', async (req) => {
    const body = putBody.parse(req.body);
    const userId = (req as AuthedRequest).userId;
    await requireEntitlement(app, userId);
    const prisma = getPrisma();
    const user = await prisma.user.findUnique({ where: { id: userId }, include: { onboarding: true } });
    if (!user?.onboarding) throw app.httpErrors.conflict('onboarding not complete');
    const now = new Date();
    const dayStart = startOfLocalDay(now, user.timezone);
    const stored = await replaceWorkouts(prisma, userId, {
      plannedFrom: dayStart,
      plannedTo: new Date(dayStart.getTime() + 7 * 86_400_000),
      healthkitFrom: new Date(dayStart.getTime() - 2 * 86_400_000),
      workouts: body.workouts.map((w) => ({
        source: w.source,
        kind: w.kind,
        start: new Date(w.start),
        durationMin: w.durationMin,
        activeKcal: w.activeKcal ?? null,
        clientId: w.clientId ?? null,
      })),
    });
    return { stored };
  });

  // Plan sessions: one, or a weekly repeat sent as its dates. Safe to retry —
  // a session the phone already sent (same clientId) isn't added twice.
  app.post('/planned', async (req) => {
    const body = plannedBody.parse(req.body);
    const userId = (req as AuthedRequest).userId;
    await requireEntitlement(app, userId);
    const prisma = getPrisma();
    const user = await prisma.user.findUnique({ where: { id: userId }, select: { timezone: true } });
    if (!user) throw app.httpErrors.notFound('no such user');
    const now = new Date();
    const list = body.sessions ?? [{ clientId: null as string | null, start: body.start! }];
    const rows = list.map((s) => ({ clientId: s.clientId, start: new Date(s.start) }));
    for (const r of rows) {
      const problem = startProblem(r.start, now, user.timezone);
      if (problem) throw app.httpErrors.badRequest(problem);
    }
    if (!body.sessions) {
      const row = await prisma.workout.create({
        data: { userId, source: 'PLANNED', kind: body.kind, start: rows[0]!.start, durationMin: body.durationMin },
      });
      return { id: row.id, sessions: [{ id: row.id, clientId: null }] };
    }
    await prisma.workout.createMany({
      data: rows.map((r) => ({
        userId,
        source: 'PLANNED' as const,
        kind: body.kind,
        start: r.start,
        durationMin: body.durationMin,
        clientId: r.clientId,
        seriesId: body.seriesId ?? null,
      })),
      skipDuplicates: true,
    });
    const saved = await prisma.workout.findMany({
      where: { userId, clientId: { in: rows.map((r) => r.clientId!) } },
      select: { id: true, clientId: true },
    });
    return { id: saved[0]?.id, sessions: saved };
  });

  /** A planned session by its id or the id the phone gave it. */
  async function findPlanned(userId: string, ref: string) {
    const row = await getPrisma().workout.findFirst({ where: { userId, OR: [{ id: ref }, { clientId: ref }] } });
    if (!row || row.source !== 'PLANNED') throw app.httpErrors.notFound('planned session not found');
    if (!canEdit(row, new Date())) throw app.httpErrors.conflict('session already started');
    return row;
  }

  /** The session and the later ones in its repeat that haven't started. */
  async function andFollowing(row: { userId: string; seriesId: string | null; start: Date; id: string }) {
    if (!row.seriesId) return [row];
    return getPrisma().workout.findMany({
      where: { userId: row.userId, seriesId: row.seriesId, source: 'PLANNED', start: { gte: row.start } },
      orderBy: { start: 'asc' },
    });
  }

  // Edit a session that hasn't started: its kind, time or length.
  app.patch('/:ref', async (req) => {
    const { ref } = z.object({ ref: z.string().min(1) }).parse(req.params);
    const body = editBody.parse(req.body);
    const userId = (req as AuthedRequest).userId;
    await requireEntitlement(app, userId);
    const prisma = getPrisma();
    const user = await prisma.user.findUnique({ where: { id: userId }, select: { timezone: true } });
    if (!user) throw app.httpErrors.notFound('no such user');
    const row = await findPlanned(userId, ref);
    const now = new Date();
    const newStart = body.start ? new Date(body.start) : row.start;
    if (body.start) {
      const problem = startProblem(newStart, now, user.timezone);
      if (problem) throw app.httpErrors.badRequest(problem);
      if (newStart <= now) throw app.httpErrors.badRequest('start has passed');
    }
    const fields = {
      ...(body.kind ? { kind: body.kind } : {}),
      ...(body.durationMin ? { durationMin: body.durationMin } : {}),
    };
    const rows = body.scope === 'following' ? await andFollowing(row) : [row];
    const starts = body.start ? followingStarts(rows, row.start, newStart, user.timezone) : new Map<string, Date>();
    await prisma.$transaction(
      rows.map((r) =>
        prisma.workout.update({
          where: { id: r.id },
          data: { ...fields, ...(starts.has(r.id) ? { start: starts.get(r.id) } : {}) },
        }),
      ),
    );
    return { updated: rows.length };
  });

  // Remove a session that hasn't started, or it and the rest of its repeat.
  app.delete('/:ref', async (req) => {
    const { ref } = z.object({ ref: z.string().min(1) }).parse(req.params);
    const { scope } = scopeQuery.parse(req.query);
    const userId = (req as AuthedRequest).userId;
    const row = await findPlanned(userId, ref);
    const rows = scope === 'following' ? await andFollowing(row) : [row];
    const result = await getPrisma().workout.deleteMany({
      where: { userId, source: 'PLANNED', id: { in: rows.map((r) => r.id) } },
    });
    return { deleted: result.count };
  });

  app.get('/', async (req) => {
    const prisma = getPrisma();
    const userId = (req as AuthedRequest).userId;
    const user = await prisma.user.findUnique({
      where: { id: userId },
      include: { onboarding: true, weightEntries: { orderBy: { measuredAt: 'desc' }, take: 1 } },
    });
    if (!user?.onboarding) throw app.httpErrors.conflict('onboarding not complete');
    const p = user.onboarding;
    const now = new Date();
    const todayISO = localDateISO(now, user.timezone);
    const windowStartISO = shiftDateISO(todayISO, -13);
    const windowStart = localDayRange(windowStartISO, user.timezone).start;
    const lastISO = shiftDateISO(todayISO, PLAN_HORIZON_DAYS);
    const rangeEnd = localDayRange(lastISO, user.timezone).end;
    const snackLookback = new Date(now.getTime() - 28 * 86_400_000);
    const [workouts, meals, snackMeals, savedMeals, restrictions] = await Promise.all([
      prisma.workout.findMany({
        where: { userId, start: { gte: windowStart, lt: rangeEnd } },
        orderBy: { start: 'asc' },
      }),
      prisma.meal.findMany({
        where: { userId, loggedAt: { gte: windowStart } },
        select: { loggedAt: true, kcal: true },
      }),
      prisma.meal.findMany({
        where: { userId, loggedAt: { gte: snackLookback } },
        select: { loggedAt: true, kcal: true, rawInput: true, items: true },
        orderBy: { loggedAt: 'desc' },
        take: 80,
      }),
      prisma.savedMeal.findMany({
        where: { userId },
        select: { name: true, kcal: true, items: true, useCount: true, lastUsedAt: true, useInCheckIns: true },
      }),
      prisma.dietaryRestriction.findMany({
        where: { userId, isHardExclusion: true },
        select: { token: true },
      }),
    ]);
    const weightKg = user.weightEntries[0]?.weightKg ?? p.weightKg ?? 80;
    const addCalories = p.trainingAddCalories ?? true;
    const days = [];
    let todayFirst: { start: Date; durationMin: number } | undefined;
    let fueledGood = 0;
    let fueledTotal = 0;
    for (let i = 0; i < 14; i += 1) {
      const date = shiftDateISO(windowStartISO, i);
      const range = localDayRange(date, user.timezone);
      const dayWorkouts = effectiveWorkouts(workouts.filter((w) => w.start >= range.start && w.start < range.end));
      const bump = trainingBump(dayWorkouts.map(asTrainingWorkout), weightKg);
      const past = date <= todayISO;
      const recorded = dayWorkouts.filter((w) => w.source === 'HEALTHKIT');
      if (past && recorded.length > 0) {
        fueledTotal += 1;
        if (
          recorded.some((w) => {
            const ended = new Date(w.start.getTime() + w.durationMin * 60_000);
            const until = ended.getTime() + REFUEL_WINDOW_MIN * 60_000;
            return meals.some((m) => m.kcal >= 250 && m.loggedAt >= ended && m.loggedAt.getTime() <= until);
          })
        ) {
          fueledGood += 1;
        }
      }
      if (date === todayISO) todayFirst = dayWorkouts[0];
      days.push({
        date,
        bumpKcal: addCalories ? bump : 0,
        rest: dayWorkouts.length === 0,
        /** Did they eat after the session: done · missed · due · planned; null on rest days. */
        refuel: refuelStatus(dayWorkouts, meals, now),
        /** All food logged that day. */
        eatenKcal: meals.filter((m) => m.loggedAt >= range.start && m.loggedAt < range.end).reduce((sum, m) => sum + m.kcal, 0),
        /** The meal that counted as the refuel, if one did. */
        refuelMeal: refuelMealFor(dayWorkouts, meals),
        workouts: dayWorkouts.map((w) => ({
          id: w.id,
          kind: w.kind,
          source: w.source,
          start: w.start.toISOString(),
          startMin: Math.floor(msSinceLocalMidnight(w.start, user.timezone) / 60_000),
          durationMin: w.durationMin,
          activeKcal: w.activeKcal,
        })),
      });
    }
    // Every session from two weeks back to the planning horizon, one list, as
    // each day counts them (a plan Apple Health also recorded shows once).
    const sessions = [];
    for (let date = windowStartISO; date <= lastISO; date = shiftDateISO(date, 1)) {
      const range = localDayRange(date, user.timezone);
      for (const w of effectiveWorkouts(workouts.filter((x) => x.start >= range.start && x.start < range.end))) {
        sessions.push({
          id: w.id,
          clientId: w.clientId,
          seriesId: w.seriesId,
          kind: w.kind,
          source: w.source,
          start: w.start.toISOString(),
          durationMin: w.durationMin,
          activeKcal: w.activeKcal,
        });
      }
    }
    const today = days.find((d) => d.date === todayISO) ?? days[0]!;
    const todayBump = today.bumpKcal;
    // What training adds today even while "Add calories" is off, so the app can
    // show the switch's effect the moment it's flipped.
    const todayFirstDay = effectiveWorkouts(workouts.filter((w) => {
      const r = localDayRange(todayISO, user.timezone);
      return w.start >= r.start && w.start < r.end;
    }));
    const trainingKcal = trainingBump(todayFirstDay.map(asTrainingWorkout), weightKg);
    const baseKcal = p.dailyKcalTarget;
    const targetKcal = applyTrainingTarget(baseKcal, todayBump, addCalories);
    const first = today.workouts[0];
    const timeline: { kind: string; atMin: number; label: string; nudge?: boolean }[] = [];
    if (first) {
      timeline.push({ kind: 'before', atMin: Math.max(0, first.startMin - 90), label: 'Before you train' });
      timeline.push({ kind: 'workout', atMin: first.startMin, label: 'Workout' });
      timeline.push({
        kind: 'refuel',
        atMin: first.startMin + first.durationMin,
        label: 'Refuel window',
      });
    }
    timeline.push({ kind: 'dinner', atMin: p.dinnerMin, label: 'Dinner' });
    const dinnerAt = new Date(localDayRange(todayISO, user.timezone).start.getTime() + p.dinnerMin * 60_000);
    const excludedTokens = excludedTokensFrom(restrictions, p.dislikedFoods);
    let snackBefore = pickSnackBefore({
      meals: snackMeals,
      workouts,
      savedMeals,
      dislikedFoods: p.dislikedFoods ?? [],
      excludedTokens,
      pantryTokens: p.pantryTokens ?? [],
      drinkableOk: p.drinkableOk ?? true,
    });
    if (!snackBefore) {
      const staples = await loadStapleFoods(prisma);
      snackBefore = pickSnackBefore({
        meals: snackMeals,
        workouts,
        savedMeals,
        dislikedFoods: p.dislikedFoods ?? [],
        excludedTokens,
        pantryTokens: p.pantryTokens ?? [],
        drinkableOk: p.drinkableOk ?? true,
        solverFoods: staples.solverFoods,
      });
    }
    return {
      addCalories,
      preWorkoutNudgeMin: p.preWorkoutNudgeMin,
      fueledWell: { good: fueledGood, total: fueledTotal },
      /** The last 14 days with how each went; `sessions` holds the sessions themselves. */
      days,
      sessions,
      /** Sessions can be planned this many days ahead. */
      horizonDays: PLAN_HORIZON_DAYS,
      /** For the phone's own estimate of what a session adds while it saves. */
      weightKg,
      today: {
        baseKcal,
        bumpKcal: todayBump,
        targetKcal,
        workouts: today.workouts,
        dinnerMin: p.dinnerMin,
        timeline,
        /** Which of today's steps are done, for the Train screen's plan. */
        steps: todaySteps(todayFirst, dinnerAt, meals, now),
        refuelWindowMin: REFUEL_WINDOW_MIN,
        trainingKcal,
        /** A snack they already eat, or a light staple that fits their foods. */
        snackBefore,
      },
    };
  });
}
