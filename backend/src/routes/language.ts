import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { requireAuth, type AuthedRequest } from '../auth/index.js';
import { getPrisma } from '../db/client.js';

/** The app tells the server which language the person chose, so push bodies and the manager's lines match. */
export async function languageRoutes(app: FastifyInstance): Promise<void> {
  app.addHook('preHandler', requireAuth(app));

  app.put('/', async (req) => {
    const { language } = z.object({ language: z.enum(['en', 'he']) }).parse(req.body);
    await getPrisma().user.update({ where: { id: (req as AuthedRequest).userId }, data: { language } });
    return { language };
  });
}
