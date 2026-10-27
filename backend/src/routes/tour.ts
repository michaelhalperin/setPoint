import type { FastifyInstance } from 'fastify';
import { requireAuth } from '../auth/index.js';
import { getPrisma } from '../db/client.js';
import { forApp, loadTour } from '../tour/index.js';

/** The app asks for the guided tour at launch; the owner edits it in /admin. */
export async function tourRoutes(app: FastifyInstance): Promise<void> {
  app.addHook('preHandler', requireAuth(app));

  app.get('/', async () => forApp(await loadTour(getPrisma())));
}
