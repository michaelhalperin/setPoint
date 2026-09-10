import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { getAnthropic } from '../ai/client.js';
import { createMealParser } from '../ai/parseMeal.js';
import { requireAuth, type AuthedRequest } from '../auth/index.js';
import { getPrisma } from '../db/client.js';
import { EmptyMealError, MealParsingUnavailableError, logMeal } from '../meals/logMeal.js';
import { listMealsForDate } from '../meals/listMeals.js';
import { MealNotFoundError, updateMeal } from '../meals/updateMeal.js';

const body = z
  .object({
    text: z.string().min(1).max(2000).optional(),
    image: z
      .object({
        data: z.string().min(1),
        mediaType: z.enum(['image/jpeg', 'image/png', 'image/webp', 'image/gif']),
      })
      .optional(),
    loggedAt: z.string().datetime().optional(),
    macros: z
      .object({
        kcal: z.number().nonnegative(),
        proteinG: z.number().nonnegative().optional(),
        carbsG: z.number().nonnegative().optional(),
        fatG: z.number().nonnegative().optional(),
      })
      .optional(),
    prescriptionId: z.string().optional(),
  })
  .refine((b) => b.text || b.image || b.macros || b.prescriptionId, {
    message: 'provide text, image, macros, or a prescriptionId',
  });

const dateQuery = z.object({
  date: z
    .string()
    .regex(/^\d{4}-\d{2}-\d{2}$/, 'date must be YYYY-MM-DD')
    .optional(),
});

const correctionBody = z.object({
  summary: z.string().trim().min(1).max(200),
  items: z
    .array(
      z.object({
        name: z.string().trim().min(1).max(120),
        quantity: z.string().trim().max(80),
        kcal: z.number().int().min(0).max(5000),
        proteinG: z.number().min(0).max(1000),
        carbsG: z.number().min(0).max(1000),
        fatG: z.number().min(0).max(1000),
      }),
    )
    .min(1)
    .max(20),
});

export async function mealRoutes(app: FastifyInstance): Promise<void> {
  app.addHook('preHandler', requireAuth(app));

  // Today's meals (or a specific local date) — listing cards on Today / Week day detail.
  app.get('/', async (req) => {
    const { date } = dateQuery.parse(req.query);
    return listMealsForDate({ prisma: getPrisma() }, (req as AuthedRequest).userId, date);
  });

  // Log a meal (§5.5). Free text or photo is AI-parsed into macros; explicit
  // macros skip the model. Resolves any open check-in.
  app.post('/', async (req) => {
    const input = body.parse(req.body);
    const client = getAnthropic();

    try {
      const result = await logMeal(
        { prisma: getPrisma(), parseMeal: client ? createMealParser(client) : null },
        (req as AuthedRequest).userId,
        {
          text: input.text,
          image: input.image,
          loggedAt: input.loggedAt ? new Date(input.loggedAt) : undefined,
          macros: input.macros,
          prescriptionId: input.prescriptionId,
        },
      );
      return result;
    } catch (err) {
      if (err instanceof MealParsingUnavailableError) throw app.httpErrors.serviceUnavailable(err.message);
      if (err instanceof EmptyMealError) throw app.httpErrors.badRequest(err.message);
      throw err;
    }
  });

  // Correct an AI estimate without deleting the meal or losing its photo.
  // Totals are derived from the corrected line items so the ledger stays coherent.
  app.patch('/:id', async (req) => {
    const { id } = z.object({ id: z.string().min(1) }).parse(req.params);
    const input = correctionBody.parse(req.body);
    try {
      const meal = await updateMeal({ prisma: getPrisma() }, (req as AuthedRequest).userId, id, input);
      return { meal };
    } catch (err) {
      if (err instanceof MealNotFoundError) throw app.httpErrors.notFound(err.message);
      throw err;
    }
  });

  // Undo a just-logged meal (e.g. the photo parse was wrong).
  app.delete('/:id', async (req) => {
    const { id } = z.object({ id: z.string().min(1) }).parse(req.params);
    const result = await getPrisma().meal.deleteMany({
      where: { id, userId: (req as AuthedRequest).userId },
    });
    if (result.count === 0) throw app.httpErrors.notFound('meal not found');
    return { deleted: true };
  });
}
