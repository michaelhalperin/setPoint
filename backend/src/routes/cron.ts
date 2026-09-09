import type { FastifyInstance, FastifyRequest } from 'fastify';
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

  // Milestone 3 replaces this stub with the deterministic confidence engine:
  // load eligible users, skip quiet hours, score, create tier-1 check-ins.
  app.post('/score', async (req) => {
    req.log.info('cron:score invoked (stub) — confidence engine lands in milestone 3');
    return { ok: true, stub: true, scored: 0, checkInsCreated: 0 };
  });
}
