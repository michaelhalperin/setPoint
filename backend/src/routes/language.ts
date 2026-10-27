import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { track } from '../analytics/events.js';
import { requireAuth, type AuthedRequest } from '../auth/index.js';
import { getPrisma } from '../db/client.js';

/** The app tells the server which language the person chose, so push bodies and the manager's lines match. */
export async function languageRoutes(app: FastifyInstance): Promise<void> {
  app.addHook('preHandler', requireAuth(app));

  app.put('/', async (req) => {
    const { language } = z.object({ language: z.enum(['en', 'he']) }).parse(req.body);
    const userId = (req as AuthedRequest).userId;
    const prisma = getPrisma();
    const before = await prisma.user.findUnique({ where: { id: userId }, select: { language: true } });
    await prisma.user.update({ where: { id: userId }, data: { language } });
    if (before && before.language !== language) await track(prisma, userId, 'language_changed', { lang: language });
    return { language };
  });
}
