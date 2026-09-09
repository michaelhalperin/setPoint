import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { getAnthropic } from '../ai/client.js';
import { createMealParser } from '../ai/parseMeal.js';
import { requireAuth, type AuthedRequest } from '../auth/index.js';
import { getPrisma } from '../db/client.js';
import { EmptyMealError, MealParsingUnavailableError, logMeal } from '../meals/logMeal.js';

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

export async function mealRoutes(app: FastifyInstance): Promise<void> {
  app.addHook('preHandler', requireAuth(app));

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
