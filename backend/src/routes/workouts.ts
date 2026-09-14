import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { requireAuth, type AuthedRequest } from '../auth/index.js';
import { getPrisma } from '../db/client.js';
import { requireEntitlement } from '../subscription/requireEntitlement.js';
import { localDateISO, localDayRange, msSinceLocalMidnight, shiftDateISO, startOfLocalDay } from '../engine/time.js';
import { applyTrainingTarget, REFUEL_WINDOW_MIN, trainingBump } from '../engine/training.js';
import { asTrainingWorkout } from '../training/day.js';
import { replaceWorkouts } from '../training/replaceWorkouts.js';

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

const plannedBody = z.object({
  kind,
  start: z.string().min(10),
  durationMin: z.number().int().min(5).max(360),
});

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

  app.post('/planned', async (req) => {
    const body = plannedBody.parse(req.body);
    const userId = (req as AuthedRequest).userId;
    await requireEntitlement(app, userId);
    const prisma = getPrisma();
    const start = new Date(body.start);
    const row = await prisma.workout.create({
      data: {
        userId,
        source: 'PLANNED',
        kind: body.kind,
        start,
        durationMin: body.durationMin,
      },
    });
    return { id: row.id };
  });

  app.delete('/:id', async (req) => {
    const { id } = z.object({ id: z.string().min(1) }).parse(req.params);
    const userId = (req as AuthedRequest).userId;
    const result = await getPrisma().workout.deleteMany({
      where: { id, userId, source: 'PLANNED' },
    });
    if (result.count === 0) throw app.httpErrors.notFound('planned session not found');
    return { deleted: true };
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
    const weekEnd = new Date(startOfLocalDay(now, user.timezone).getTime() + 7 * 86_400_000);
    const [workouts, meals] = await Promise.all([
      prisma.workout.findMany({
        where: { userId, start: { gte: windowStart, lt: weekEnd } },
        orderBy: { start: 'asc' },
      }),
      prisma.meal.findMany({
        where: { userId, loggedAt: { gte: windowStart } },
        select: { loggedAt: true, kcal: true },
      }),
    ]);
    const weightKg = user.weightEntries[0]?.weightKg ?? p.weightKg ?? 80;
    const addCalories = p.trainingAddCalories ?? true;
    const days = [];
    let fueledGood = 0;
    let fueledTotal = 0;
    for (let i = 0; i < 14; i += 1) {
      const date = shiftDateISO(windowStartISO, i);
      const range = localDayRange(date, user.timezone);
      const dayWorkouts = workouts.filter((w) => w.start >= range.start && w.start < range.end);
      const bump = trainingBump(dayWorkouts.map(asTrainingWorkout), weightKg);
      const past = date <= todayISO;
      if (past && dayWorkouts.length > 0) {
        fueledTotal += 1;
        if (
          dayWorkouts.some((w) => {
            const ended = new Date(w.start.getTime() + w.durationMin * 60_000);
            const until = ended.getTime() + REFUEL_WINDOW_MIN * 60_000;
            return meals.some((m) => m.kcal >= 250 && m.loggedAt >= ended && m.loggedAt.getTime() <= until);
          })
        ) {
          fueledGood += 1;
        }
      }
      if (i >= 7) {
        days.push({
          date,
          bumpKcal: addCalories ? bump : 0,
          rest: dayWorkouts.length === 0,
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
    }
    const today = days.find((d) => d.date === todayISO) ?? days[0]!;
    const todayBump = today.bumpKcal;
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
    return {
      addCalories,
      preWorkoutNudgeMin: p.preWorkoutNudgeMin,
      fueledWell: { good: fueledGood, total: fueledTotal },
      days,
      today: {
        baseKcal,
        bumpKcal: todayBump,
        targetKcal,
        workouts: today.workouts,
        dinnerMin: p.dinnerMin,
        timeline,
      },
    };
  });
}
