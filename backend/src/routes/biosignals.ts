import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { requireAuth, type AuthedRequest } from '../auth/index.js';
import { getPrisma } from '../db/client.js';

/**
 * The app computes HRV/RHR deviation from personal baseline **on-device** and
 * sends only the derived z-scores (plan §4 — raw time series never leaves the
 * device). Negative HRV / positive RHR = the under-fuelling direction.
 */
const body = z.object({
  hrvDeviation: z.number().finite(),
  rhrDeviation: z.number().finite().optional(),
  source: z.string().min(1).max(40).default('healthkit'),
});

export async function biosignalRoutes(app: FastifyInstance): Promise<void> {
  app.addHook('preHandler', requireAuth(app));

  app.post('/', async (req) => {
    const { hrvDeviation, rhrDeviation, source } = body.parse(req.body);
    const userId = (req as AuthedRequest).userId;
    const prisma = getPrisma();
    const now = new Date();

    await prisma.$transaction([
      prisma.biosignalState.upsert({
        where: { userId },
        create: { userId, hrvDeviation, rhrDeviation: rhrDeviation ?? null, source },
        update: { hrvDeviation, rhrDeviation: rhrDeviation ?? null, source },
      }),
      prisma.biosignalReading.create({
        data: { userId, capturedAt: now, hrvDeviation, rhrDeviation: rhrDeviation ?? null, source },
      }),
    ]);

    return { ok: true };
  });
}
