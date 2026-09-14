import type { FastifyInstance, FastifyRequest } from 'fastify';
import { pruneAiUsage } from '../ai/quota.js';
import { getPrisma } from '../db/client.js';
import { pruneRateLimitBuckets } from '../http/rateLimit.js';
import { recordHeartbeat } from '../jobs/heartbeat.js';
import { retryPhotoDeletions, type PhotoCleanupSummary } from '../photos/cleanup.js';
import { getPhotoStore } from '../photos/store.js';
import { runScoreConfidenceJob } from '../jobs/scoreConfidence.js';
import { runSettleDayJob } from '../jobs/settleDay.js';
import { createManagerVoice } from '../managerVoice/factory.js';
import { captureError, flushSentry } from '../observability/sentry.js';
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
      const started = new Date();
      try {
        const summary = await runScoreConfidenceJob({
          prisma: getPrisma(),
          push: createPushSender(),
          voice: createManagerVoice(),
        });
        req.log.info(summary, 'cron:score complete');
        await recordHeartbeat(getPrisma(), 'score', started, true, summary);
        await flushSentry();
        return summary;
      } catch (err) {
        await recordHeartbeat(getPrisma(), 'score', started, false, { error: String(err) }).catch(() => {});
        throw err;
      }
    },
  });

  // Daily settlement (§5.7): write yesterday's DayOutcome for every user, then
  // drop AI-usage rows the quota no longer reads.
  app.route({
    method: ['GET', 'POST'],
    url: '/settle',
    handler: async (req) => {
      const summary = await runSettleDayJob({ prisma: getPrisma(), voice: createManagerVoice() });

      let aiUsagePruned = 0;
      try {
        aiUsagePruned = await pruneAiUsage(getPrisma());
      } catch (err) {
        req.log.warn({ err }, 'cron:settle AI-usage prune failed');
        captureError(err, { tags: { job: 'prune-ai-usage' } });
      }

      let rateLimitPruned = 0;
      try {
        rateLimitPruned = await pruneRateLimitBuckets(getPrisma());
      } catch (err) {
        req.log.warn({ err }, 'cron:settle rate-limit prune failed');
      }

      // Vercel Hobby allows only daily crons, so photo cleanup rides along here.
      let photoCleanup: PhotoCleanupSummary | null = null;
      const photos = getPhotoStore();
      if (photos) {
        try {
          photoCleanup = await retryPhotoDeletions(getPrisma(), photos);
          if (photoCleanup.givenUp > 0) {
            captureError(new Error(`${photoCleanup.givenUp} photo deletes need manual cleanup`), {
              tags: { job: 'photo-cleanup' },
            });
          }
        } catch (err) {
          req.log.warn({ err }, 'cron:settle photo cleanup failed');
          captureError(err, { tags: { job: 'photo-cleanup' } });
        }
      }

      req.log.info({ ...summary, aiUsagePruned, rateLimitPruned, photoCleanup }, 'cron:settle complete');
      await flushSentry();
      return { ...summary, aiUsagePruned, rateLimitPruned, photoCleanup };
    },
  });

  // Retry failed photo deletes now (the daily settle run does this too).
  app.route({
    method: ['GET', 'POST'],
    url: '/cleanup-photos',
    handler: async (req) => {
      const photos = getPhotoStore();
      if (!photos) return { attempted: 0, deleted: 0, failed: 0, givenUp: 0, note: 'photo store unconfigured' };
      const summary = await retryPhotoDeletions(getPrisma(), photos);
      req.log.info(summary, 'cron:cleanup-photos complete');
      return summary;
    },
  });
}
