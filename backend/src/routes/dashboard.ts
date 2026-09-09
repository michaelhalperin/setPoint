import type { FastifyInstance } from 'fastify';
import { requireAuth, type AuthedRequest } from '../auth/index.js';
import { OnboardingIncompleteError, buildHome, buildSettlement } from '../dashboard/index.js';
import { getPrisma } from '../db/client.js';
import { createManagerVoice } from '../managerVoice/factory.js';

export async function dashboardRoutes(app: FastifyInstance): Promise<void> {
  app.addHook('preHandler', requireAuth(app));

  // Home dashboard — running ledger, goal-framed, with the manager's note (§5.2).
  app.get('/home', async (req) => {
    try {
      return await buildHome(
        { prisma: getPrisma(), voice: createManagerVoice() },
        (req as AuthedRequest).userId,
      );
    } catch (err) {
      if (err instanceof OnboardingIncompleteError) throw app.httpErrors.conflict(err.message);
      throw err;
    }
  });

  // Settlement — the last 7 settled days plus today's live projection (§5.7).
  app.get('/settlement', async (req) => {
    try {
      return await buildSettlement({ prisma: getPrisma() }, (req as AuthedRequest).userId);
    } catch (err) {
      if (err instanceof OnboardingIncompleteError) throw app.httpErrors.conflict(err.message);
      throw err;
    }
  });
}
