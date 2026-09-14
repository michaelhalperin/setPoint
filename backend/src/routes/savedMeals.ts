import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { requireAuth, type AuthedRequest } from '../auth/index.js';
import { getPrisma } from '../db/client.js';
import { currentMealSlot } from '../engine/mealSchedule.js';
import { msSinceLocalMidnight } from '../engine/time.js';
import { mealItemsSchema } from '../meals/items.js';
import {
  SavedMealNotFoundError,
  SUGGEST_SLOTS,
  createSavedMeal,
  deleteSavedMeal,
  listSavedMeals,
  updateSavedMeal,
} from '../savedMeals/index.js';

const writeBody = z.object({
  name: z.string().trim().min(1).max(80),
  items: mealItemsSchema,
  suggestSlot: z.enum(SUGGEST_SLOTS).nullable().optional(),
  useInCheckIns: z.boolean().optional(),
});

const idParams = z.object({ id: z.string().min(1) });
const listQuery = z.object({
  now: z.string().datetime().optional(),
});

export async function savedMealRoutes(app: FastifyInstance): Promise<void> {
  app.addHook('preHandler', requireAuth(app));

  app.get('/', async (req) => {
    const { now: nowRaw } = listQuery.parse(req.query);
    const userId = (req as AuthedRequest).userId;
    const prisma = getPrisma();
    const user = await prisma.user.findUnique({
      where: { id: userId },
      select: { timezone: true, onboarding: { select: { breakfastMin: true, lunchMin: true, dinnerMin: true } } },
    });
    const now = nowRaw ? new Date(nowRaw) : new Date();
    const timezone = user?.timezone ?? 'UTC';
    const times = user?.onboarding ?? { breakfastMin: 480, lunchMin: 780, dinnerMin: 1140 };
    const nowMin = Math.floor(msSinceLocalMidnight(now, timezone) / 60_000);
    return { meals: await listSavedMeals(prisma, userId, { nowMin, times }), slot: currentMealSlot(nowMin, times) };
  });

  app.post('/', async (req) => {
    const input = writeBody.parse(req.body);
    const meal = await createSavedMeal(getPrisma(), (req as AuthedRequest).userId, input);
    return { meal };
  });

  app.patch('/:id', async (req) => {
    const { id } = idParams.parse(req.params);
    const input = writeBody.parse(req.body);
    try {
      const meal = await updateSavedMeal(getPrisma(), (req as AuthedRequest).userId, id, input);
      return { meal };
    } catch (err) {
      if (err instanceof SavedMealNotFoundError) throw app.httpErrors.notFound(err.message);
      throw err;
    }
  });

  app.delete('/:id', async (req) => {
    const { id } = idParams.parse(req.params);
    try {
      await deleteSavedMeal(getPrisma(), (req as AuthedRequest).userId, id);
      return { deleted: true };
    } catch (err) {
      if (err instanceof SavedMealNotFoundError) throw app.httpErrors.notFound(err.message);
      throw err;
    }
  });
}
