import type { FastifyInstance, FastifyRequest } from 'fastify';
import { z } from 'zod';
import { getPrisma } from '../db/client.js';
import { env } from '../env.js';
import {
  buildBetaMetrics,
  type CheckInMetricRecord,
  type CheckInStatusName,
} from '../metrics/betaMetrics.js';

/** A meal logged this many minutes before a check-in fired ⇒ likely false positive. */
const FALSE_POSITIVE_WINDOW_MIN = 90;
const DEFAULT_RANGE_DAYS = 21;

/** Protects the beta metrics endpoint. Uses ADMIN_SECRET, or CRON_SECRET if unset. */
function adminSecret(): string {
  return env.ADMIN_SECRET || env.CRON_SECRET;
}

function isAuthorized(req: FastifyRequest): boolean {
  const auth = req.headers.authorization;
  const bearer = auth?.startsWith('Bearer ') ? auth.slice(7) : undefined;
  const header = req.headers['x-admin-secret'];
  const secret = adminSecret();
  return bearer === secret || header === secret;
}

const rangeQuery = z.object({
  from: z.string().datetime().optional(),
  to: z.string().datetime().optional(),
});

export async function adminRoutes(app: FastifyInstance): Promise<void> {
  app.addHook('preHandler', async (req) => {
    if (!isAuthorized(req)) throw app.httpErrors.unauthorized('bad or missing admin secret');
  });

  // Beta tuning dashboard data (§8): check-in volume, feedback, and the
  // false-positive rate to tune the confidence weights against.
  app.get('/metrics', async (req) => {
    const { from, to } = rangeQuery.parse(req.query);
    const toDate = to ? new Date(to) : new Date();
    const fromDate = from
      ? new Date(from)
      : new Date(toDate.getTime() - DEFAULT_RANGE_DAYS * 24 * 3_600_000);

    const prisma = getPrisma();
    const checkIns = await prisma.checkIn.findMany({
      where: { deliveredAt: { gte: fromDate, lte: toDate } },
      select: {
        userId: true,
        tier: true,
        status: true,
        deferCount: true,
        feedbackPositive: true,
        deliveredAt: true,
        confidenceScore: { select: { score: true } },
      },
    });

    // One pass for "ate shortly before the check-in": pull every meal for the
    // involved users across the whole range (+ the lookback window) and match.
    const userIds = [...new Set(checkIns.map((c) => c.userId))];
    const meals = userIds.length
      ? await prisma.meal.findMany({
          where: {
            userId: { in: userIds },
            loggedAt: {
              gte: new Date(fromDate.getTime() - FALSE_POSITIVE_WINDOW_MIN * 60_000),
              lte: toDate,
            },
          },
          select: { userId: true, loggedAt: true },
        })
      : [];

    const mealsByUser = new Map<string, number[]>();
    for (const m of meals) {
      const list = mealsByUser.get(m.userId) ?? [];
      list.push(m.loggedAt.getTime());
      mealsByUser.set(m.userId, list);
    }

    const windowMs = FALSE_POSITIVE_WINDOW_MIN * 60_000;
    const records: CheckInMetricRecord[] = checkIns.map((c) => {
      const firedAt = c.deliveredAt?.getTime() ?? 0;
      const ateShortlyBefore = (mealsByUser.get(c.userId) ?? []).some(
        (t) => t <= firedAt && t >= firedAt - windowMs,
      );
      return {
        tier: c.tier,
        status: c.status as CheckInStatusName,
        deferCount: c.deferCount,
        feedbackPositive: c.feedbackPositive,
        firedConfidence: c.confidenceScore?.score ?? null,
        ateShortlyBefore,
      };
    });

    const metrics = buildBetaMetrics(records, {
      from: fromDate,
      to: toDate,
      falsePositiveWindowMinutes: FALSE_POSITIVE_WINDOW_MIN,
    });

    req.log.info({ total: metrics.checkIns.total }, 'admin:metrics');
    return metrics;
  });
}
