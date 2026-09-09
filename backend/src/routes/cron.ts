import type { FastifyInstance, FastifyRequest } from 'fastify';
import { getPrisma } from '../db/client.js';
import { runScoreConfidenceJob } from '../jobs/scoreConfidence.js';
import { createManagerVoice } from '../managerVoice/factory.js';
import { createPushSender } from '../push/factory.js';
import { env } from '../env.js';

/**
 * Vercel Cron calls these endpoints with `Authorization: Bearer <CRON_SECRET>`.
 * Manual / GitHub-Actions triggering can instead send `x-cron-secret: <secret>`.
 */
function isAuthorized(req: FastifyRequest): boolean {
  const auth = req.headers.authorization;
  const bearer = auth?.startsWith('Bearer ') ? auth.slice(7) : undefined;
  const headerSecret = req.headers['x-cron-secret'];
  return bearer === env.CRON_SECRET || headerSecret === env.CRON_SECRET;
}

export async function cronRoutes(app: FastifyInstance): Promise<void> {
  app.addHook('preHandler', async (req) => {
    if (!isAuthorized(req)) throw app.httpErrors.unauthorized('bad or missing cron secret');
  });

  // The deterministic confidence engine (§2): score eligible users, advance
  // open check-ins through the escalation state machine, fire when the score
  // clears the threshold.
  app.post('/score', async (req) => {
    const summary = await runScoreConfidenceJob({
      prisma: getPrisma(),
      push: createPushSender(),
      voice: createManagerVoice(),
    });
    req.log.info(summary, 'cron:score complete');
    return summary;
  });
}
