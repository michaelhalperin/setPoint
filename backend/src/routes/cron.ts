import type { FastifyInstance, FastifyRequest } from 'fastify';
import { buildDigest, storeDigest } from '../admin/digest.js';
import { pruneAiUsage } from '../ai/quota.js';
import { getPrisma } from '../db/client.js';
import { pruneRateLimitBuckets } from '../http/rateLimit.js';
import { ranTooRecently, recordHeartbeat } from '../jobs/heartbeat.js';
import { retryPhotoDeletions, type PhotoCleanupSummary } from '../photos/cleanup.js';
import { getPhotoStore } from '../photos/store.js';
import { runScoreConfidenceJob } from '../jobs/scoreConfidence.js';
import { runSettleDayJob } from '../jobs/settleDay.js';
import { createManagerVoice } from '../managerVoice/factory.js';
import { captureError, flushSentry } from '../observability/sentry.js';
import { createPushSender } from '../push/factory.js';
import { env } from '../env.js';

/**
 * Schedulers that call these:
 *   - /score every few minutes from an external pinger (and every 15 from GitHub Actions as a
 *     backup), with `x-cron-secret: <secret>`. Vercel's Hobby plan only allows daily crons.
 *     A call within 2 minutes of the last run is skipped, so two schedulers can't double-send.
 *   - /settle daily from Vercel Cron, with `Authorization: Bearer <CRON_SECRET>`.
 * Either header is accepted on both routes, so manual triggering works too.
 */
function isAuthorized(req: FastifyRequest): boolean {
  const auth = req.headers.authorization;
  const bearer = auth?.startsWith('Bearer ') ? auth.slice(7) : undefined;
  const headerSecret = req.headers['x-cron-secret'];
  return bearer === env.CRON_SECRET || headerSecret === env.CRON_SECRET;
}

/** Raw analytics events older than this are dropped by the digest job. */
const EVENT_RETENTION_DAYS = 180;

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
      const last = await getPrisma().schedulerHeartbeat.findUnique({ where: { job: 'score' }, select: { lastRunAt: true } });
      if (ranTooRecently(last?.lastRunAt)) return { skipped: 'ran_recently', lastRunAt: last!.lastRunAt };
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

  // Usage digest each morning, plus the weekly one on Mondays. Stored in AppConfig for the
  // dashboard's Usage tab; also drops analytics events past the retention window.
  app.route({
    method: ['GET', 'POST'],
    url: '/digest',
    handler: async (req) => {
      const now = new Date();
      const periods: Array<'daily' | 'weekly'> = now.getUTCDay() === 1 ? ['daily', 'weekly'] : ['daily'];
      const digests = [];
      for (const period of periods) {
        const digest = await buildDigest(getPrisma(), period, now);
        await storeDigest(getPrisma(), digest);
        digests.push(digest);
      }
      const cutoff = new Date(now.getTime() - EVENT_RETENTION_DAYS * 86_400_000);
      const pruned = await getPrisma().analyticsEvent.deleteMany({ where: { occurredAt: { lt: cutoff } } });
      req.log.info({ periods, pruned: pruned.count }, 'cron:digest complete');
      return { digests, pruned: pruned.count };
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
