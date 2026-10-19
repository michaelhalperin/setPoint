import type { FastifyInstance } from 'fastify';
import { requireAuth, type AuthedRequest } from '../auth/index.js';
import { getPrisma } from '../db/client.js';
import { flagsForUser } from '../flags/index.js';

/** The app asks which features are on for its user, at launch. */
export async function flagRoutes(app: FastifyInstance): Promise<void> {
  app.addHook('preHandler', requireAuth(app));

  app.get('/', async (req) => ({ flags: await flagsForUser(getPrisma(), (req as AuthedRequest).userId) }));
}
