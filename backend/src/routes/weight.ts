import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { requireAuth, type AuthedRequest } from '../auth/index.js';
import { OnboardingIncompleteError } from '../dashboard/home.js';
import { getPrisma } from '../db/client.js';
import { InvalidWeightError, logWeight } from '../weight/logWeight.js';

const body = z.object({
  weightKg: z.number().positive().max(400),
  measuredAt: z.string().datetime().optional(),
  source: z.enum(['manual', 'healthkit']).optional(),
});

export async function weightRoutes(app: FastifyInstance): Promise<void> {
  app.addHook('preHandler', requireAuth(app));

  // Log a weigh-in (§5.1, M16). Reaching the goal flips it to MAINTAIN and
  // returns the fresh targets.
  app.post('/', async (req) => {
    const input = body.parse(req.body);
    try {
      return await logWeight({ prisma: getPrisma() }, (req as AuthedRequest).userId, {
        weightKg: input.weightKg,
        measuredAt: input.measuredAt ? new Date(input.measuredAt) : undefined,
        source: input.source,
      });
    } catch (err) {
      if (err instanceof OnboardingIncompleteError) throw app.httpErrors.conflict(err.message);
      if (err instanceof InvalidWeightError) throw app.httpErrors.badRequest(err.message);
      throw err;
    }
  });

  // Recent entries — for a simple weight history / chart.
  app.get('/', async (req) => {
    const { limit } = z.object({ limit: z.coerce.number().int().min(1).max(180).default(60) }).parse(req.query);
    const rows = await getPrisma().weightEntry.findMany({
      where: { userId: (req as AuthedRequest).userId },
      orderBy: { measuredAt: 'desc' },
      take: limit,
    });
    return {
      entries: rows.map((r) => ({
        id: r.id,
        weightKg: r.weightKg,
        measuredAt: r.measuredAt.toISOString(),
        source: r.source,
      })),
    };
  });
}
