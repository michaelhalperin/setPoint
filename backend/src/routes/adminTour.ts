import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { getPrisma } from '../db/client.js';
import {
  DEFAULT_TOUR,
  REFERENCE_SCREEN,
  anchorsForAdmin,
  loadTour,
  resetTour,
  saveTour,
  tourProblems,
  tourStepSchema,
} from '../tour/index.js';
import { requireAdmin } from './admin.js';

const saveBody = z.object({
  steps: z.array(tourStepSchema).max(20),
  /** Show the tour once more to everyone who has already seen it. */
  bumpRevision: z.boolean().default(false),
});

/** Edit the guided tour from the admin dashboard. */
export async function adminTourRoutes(app: FastifyInstance): Promise<void> {
  app.addHook('preHandler', requireAdmin(app));

  app.get('/tour', async () => ({
    tour: await loadTour(getPrisma()),
    defaults: DEFAULT_TOUR,
    anchors: anchorsForAdmin(),
    screen: REFERENCE_SCREEN,
  }));

  app.put('/tour', async (req) => {
    const body = saveBody.parse(req.body);
    const prisma = getPrisma();
    const current = await loadTour(prisma);
    const next = { steps: body.steps, revision: current.revision + (body.bumpRevision ? 1 : 0) };
    const problem = tourProblems(next);
    if (problem) throw app.httpErrors.badRequest(problem);
    return { tour: await saveTour(prisma, next) };
  });

  app.delete('/tour', async () => {
    const prisma = getPrisma();
    return { tour: await resetTour(prisma, await loadTour(prisma)) };
  });
}
