import type { FastifyInstance } from 'fastify';
import { requireAuth, type AuthedRequest } from '../auth/index.js';
import { OnboardingIncompleteError } from '../dashboard/home.js';
import { getPrisma } from '../db/client.js';
import { buildBurnInsight } from '../engine/burnInsight.js';

export async function insightRoutes(app: FastifyInstance): Promise<void> {
  app.addHook('preHandler', requireAuth(app));

  app.get('/burn', async (req) => {
    try {
      return await buildBurnInsight(getPrisma(), (req as AuthedRequest).userId);
    } catch (err) {
      if (err instanceof OnboardingIncompleteError) throw app.httpErrors.conflict(err.message);
      throw err;
    }
  });
}
