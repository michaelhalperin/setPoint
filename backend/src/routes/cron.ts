import type { FastifyInstance, FastifyRequest } from 'fastify';
import { getPrisma } from '../db/client.js';
import { runScoreConfidenceJob } from '../jobs/scoreConfidence.js';
import { runSettleDayJob } from '../jobs/settleDay.js';
import { createManagerVoice } from '../managerVoice/factory.js';
import { flushSentry } from '../observability/sentry.js';
import { createPushSender } from '../push/factory.js';
import { env } from '../env.js';

/**
 * Two schedulers call these:
 *   - /score every 15 minutes from GitHub Actions (.github/workflows/score-checkins.yml),
 *     with `x-cron-secret: <secret>` — Vercel's Hobby plan only allows daily crons.
 *   - /settle daily from Vercel Cron, with `Authorization: Bearer <CRON_SECRET>`.
 * Either header is accepted on both routes, so manual triggering works too.
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
  app.route({
    method: ['GET', 'POST'],
    url: '/score',
    handler: async (req) => {
      const summary = await runScoreConfidenceJob({
        prisma: getPrisma(),
        push: createPushSender(),
        voice: createManagerVoice(),
      });
      req.log.info(summary, 'cron:score complete');
      await flushSentry();
      return summary;
    },
  });

  // Daily settlement (§5.7): write yesterday's DayOutcome for every user.
  app.route({
    method: ['GET', 'POST'],
    url: '/settle',
    handler: async (req) => {
      const summary = await runSettleDayJob({ prisma: getPrisma(), voice: createManagerVoice() });
      req.log.info(summary, 'cron:settle complete');
      await flushSentry();
      return summary;
    },
  });
}
