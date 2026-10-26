import type { FastifyInstance } from 'fastify';
import { requireAuth } from '../auth/index.js';
import { getPrisma } from '../db/client.js';
import { loadTour } from '../tour/index.js';

/** The app asks for the guided tour at launch; the owner edits it in /admin. */
export async function tourRoutes(app: FastifyInstance): Promise<void> {
  app.addHook('preHandler', requireAuth(app));

  app.get('/', async () => loadTour(getPrisma()));
}
