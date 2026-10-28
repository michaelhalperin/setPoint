import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { buildDigest } from '../admin/digest.js';
import { gatherUsage } from '../admin/usage.js';
import { getPrisma } from '../db/client.js';
import { requireAdmin } from './admin.js';

const usageQuery = z.object({
  days: z.coerce.number().int().min(1).max(90).default(14),
  group: z.string().optional(),
});

const digestQuery = z.object({ period: z.enum(['daily', 'weekly']).default('daily') });

/** Usage numbers for the dashboard's Usage tab: activity, retention, adoption, digests. */
export async function adminUsageRoutes(app: FastifyInstance): Promise<void> {
  app.addHook('preHandler', requireAdmin(app));

  app.get('/usage', async (req) => {
    const q = usageQuery.parse(req.query);
    return gatherUsage(getPrisma(), { days: q.days, group: q.group });
  });

  // A fresh digest on demand (the cron stores the same one each morning).
  app.get('/usage/digest', async (req) => {
    const q = digestQuery.parse(req.query);
    return buildDigest(getPrisma(), q.period);
  });
}
