import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { requireAuth, type AuthedRequest } from '../auth/index.js';
import { getPrisma } from '../db/client.js';
import { requireEntitlement } from '../subscription/requireEntitlement.js';
import { localDateISO } from '../engine/time.js';

const body = z.object({
  level: z.enum(['HUNGRY', 'NORMAL', 'LOW']),
});

export async function appetiteRoutes(app: FastifyInstance): Promise<void> {
  app.addHook('preHandler', requireAuth(app));

  app.put('/today', async (req) => {
    const { level } = body.parse(req.body);
    const userId = (req as AuthedRequest).userId;
    await requireEntitlement(app, userId);
    const prisma = getPrisma();
    const user = await prisma.user.findUnique({ where: { id: userId }, select: { timezone: true } });
    if (!user) throw app.httpErrors.notFound('user not found');
    const localDate = localDateISO(new Date(), user.timezone);
    const row = await prisma.dayAppetite.upsert({
      where: { userId_localDate: { userId, localDate } },
      create: { userId, localDate, level },
      update: { level },
    });
    return { date: row.localDate, level: row.level };
  });
}
