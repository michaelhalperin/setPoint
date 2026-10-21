import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { nutritionOverview, personDays, weightTrends, type PersonTargets } from '../analytics/nutrition.js';
import { getPrisma } from '../db/client.js';
import { toMealSummaries } from '../meals/summary.js';
import { getPhotoStore } from '../photos/store.js';
import { requireAdmin } from './admin.js';

const mealsQuery = z.object({
  userId: z.string().optional(),
  cohort: z.string().optional(),
  source: z.enum(['TEXT', 'PHOTO', 'SAVED', 'BARCODE', 'CATALOG', 'PRESCRIPTION']).optional(),
  /** Older than this — for "load more". */
  before: z.string().datetime().optional(),
  limit: z.coerce.number().int().min(1).max(200).default(60),
});

const rangeQuery = z.object({
  from: z.string().datetime().optional(),
  to: z.string().datetime().optional(),
  cohort: z.string().optional(),
});

const MEAL_FIELDS = {
  id: true,
  userId: true,
  loggedAt: true,
  kcal: true,
  proteinG: true,
  carbsG: true,
  fatG: true,
  source: true,
  rawInput: true,
  photoUrl: true,
  photoKey: true,
  notes: true,
  items: true,
  parseConfidence: true,
  parseQuality: true,
} as const;

/** Which of these meals were corrected with Fix (from the meal_fixed events). */
async function fixedMealIds(userIds: string[], since: Date): Promise<Set<string>> {
  if (!userIds.length) return new Set();
  const events = await getPrisma().analyticsEvent.findMany({
    where: { name: 'meal_fixed', userId: { in: userIds }, occurredAt: { gte: since } },
    select: { props: true },
  });
  return new Set(
    events
      .map((e) => (e.props as { mealId?: unknown } | null)?.mealId)
      .filter((id): id is string => typeof id === 'string'),
  );
}

/**
 * What people eat and weigh, for the owner: a meals feed with photos, one
 * person's page, and food and weight numbers across a cohort. Read straight from
 * meals, day results and weigh-ins.
 */
export async function adminInsightRoutes(app: FastifyInstance): Promise<void> {
  app.addHook('preHandler', requireAdmin(app));

  app.get('/meals', async (req) => {
    const q = mealsQuery.parse(req.query);
    const prisma = getPrisma();
    const rows = await prisma.meal.findMany({
      where: {
        ...(q.userId ? { userId: q.userId } : {}),
        ...(q.cohort ? { user: { cohort: q.cohort } } : {}),
        ...(q.source ? { source: q.source } : {}),
        ...(q.before ? { loggedAt: { lt: new Date(q.before) } } : {}),
      },
      select: { ...MEAL_FIELDS, user: { select: { id: true, email: true, cohort: true } } },
      orderBy: { loggedAt: 'desc' },
      take: q.limit,
    });
    const summaries = await toMealSummaries(rows, getPhotoStore());
    const oldest = rows.length ? rows[rows.length - 1]!.loggedAt : new Date();
    const fixed = await fixedMealIds([...new Set(rows.map((r) => r.userId))], new Date(oldest.getTime() - 86_400_000));
    return {
      meals: summaries.map((m, i) => ({ ...m, fixed: fixed.has(m.id), user: rows[i]!.user })),
      nextBefore: rows.length === q.limit ? oldest.toISOString() : null,
    };
  });

  // One person: their plan, last 14 days against target, meals, weight, check-ins.
  app.get('/users/:id/profile', async (req) => {
    const { id } = z.object({ id: z.string().min(1) }).parse(req.params);
    const prisma = getPrisma();
    const user = await prisma.user.findUnique({
      where: { id },
      select: {
        id: true,
        email: true,
        role: true,
        cohort: true,
        timezone: true,
        createdAt: true,
        accessGrantedAt: true,
        inviteCode: { select: { code: true } },
        onboarding: {
          select: {
            goal: true,
            mode: true,
            dailyKcalTarget: true,
            dailyProteinTargetG: true,
            weightKg: true,
            startWeightKg: true,
            targetWeightKg: true,
            paceKgPerWeek: true,
            appetiteMode: true,
            completedAt: true,
          },
        },
      },
    });
    if (!user) throw app.httpErrors.notFound('no such user');

    const now = new Date();
    const since14 = new Date(now.getTime() - 15 * 86_400_000);
    const [recentMeals, mealRows, outcomes, weights, checkIns, lastEvent, mealCount] = await Promise.all([
      prisma.meal.findMany({ where: { userId: id, loggedAt: { gte: since14 } }, select: { userId: true, loggedAt: true, kcal: true, proteinG: true } }),
      prisma.meal.findMany({ where: { userId: id }, select: MEAL_FIELDS, orderBy: { loggedAt: 'desc' }, take: 60 }),
      prisma.dayOutcome.findMany({ where: { userId: id, date: { gte: since14 } }, select: { userId: true, date: true, kind: true, kcalConsumed: true, kcalTarget: true } }),
      prisma.weightEntry.findMany({ where: { userId: id, measuredAt: { gte: new Date(now.getTime() - 180 * 86_400_000) } }, select: { weightKg: true, measuredAt: true, source: true }, orderBy: { measuredAt: 'asc' } }),
      prisma.checkIn.findMany({ where: { userId: id, createdAt: { gte: since14 } }, select: { id: true, createdAt: true, kind: true, slot: true, tier: true, status: true, feedbackPositive: true }, orderBy: { createdAt: 'desc' }, take: 60 }),
      prisma.analyticsEvent.findFirst({ where: { userId: id }, orderBy: { occurredAt: 'desc' }, select: { occurredAt: true, name: true } }),
      prisma.meal.count({ where: { userId: id } }),
    ]);

    const targets: PersonTargets = {
      timezone: user.timezone,
      kcalTarget: user.onboarding?.dailyKcalTarget ?? null,
      proteinTargetG: user.onboarding?.dailyProteinTargetG ?? null,
    };
    const meals = await toMealSummaries(mealRows, getPhotoStore());
    const fixed = await fixedMealIds([id], mealRows.length ? mealRows[mealRows.length - 1]!.loggedAt : now);
    return {
      user,
      days: personDays(recentMeals, targets, outcomes, 14, now),
      meals: meals.map((m) => ({ ...m, fixed: fixed.has(m.id) })),
      mealCount,
      weights,
      checkIns,
      lastActive: lastEvent ? { at: lastEvent.occurredAt, event: lastEvent.name } : null,
    };
  });

  // Calories against target, protein, and weight change, for everyone or a cohort.
  app.get('/nutrition', async (req) => {
    const q = rangeQuery.parse(req.query);
    const to = q.to ? new Date(q.to) : new Date();
    const from = q.from ? new Date(q.from) : new Date(to.getTime() - 14 * 86_400_000);
    const userWhere = q.cohort ? { user: { cohort: q.cohort } } : {};
    const prisma = getPrisma();
    const [outcomes, meals, weights] = await Promise.all([
      prisma.dayOutcome.findMany({
        where: { date: { gte: new Date(from.toISOString().slice(0, 10)), lte: to }, ...userWhere },
        select: { userId: true, date: true, kind: true, kcalConsumed: true, kcalTarget: true },
        take: 50_000,
      }),
      prisma.meal.findMany({
        where: { loggedAt: { gte: from, lte: to }, ...userWhere },
        select: { userId: true, loggedAt: true, kcal: true, proteinG: true },
        take: 100_000,
      }),
      prisma.weightEntry.findMany({
        where: { measuredAt: { gte: from, lte: to }, ...userWhere },
        select: { userId: true, weightKg: true, measuredAt: true },
        take: 50_000,
      }),
    ]);
    const userIds = [...new Set([...meals.map((m) => m.userId), ...weights.map((w) => w.userId)])];
    const people = await prisma.user.findMany({
      where: { id: { in: userIds } },
      select: { id: true, timezone: true, onboarding: { select: { goal: true, dailyKcalTarget: true, dailyProteinTargetG: true } } },
    });
    const targets = new Map(
      people.map((p) => [
        p.id,
        { timezone: p.timezone, kcalTarget: p.onboarding?.dailyKcalTarget ?? null, proteinTargetG: p.onboarding?.dailyProteinTargetG ?? null },
      ]),
    );
    const goals = new Map(people.filter((p) => p.onboarding).map((p) => [p.id, p.onboarding!.goal as string]));
    return {
      range: { from: from.toISOString(), to: to.toISOString() },
      ...nutritionOverview(outcomes, meals, targets),
      weight: weightTrends(weights, goals),
    };
  });
}
