import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { requireAuth, type AuthedRequest } from '../auth/index.js';
import { getPrisma } from '../db/client.js';

const registerBody = z.object({
  token: z.string().min(1).max(400),
  kind: z.enum(['alert', 'live_activity_start']).default('alert'),
  environment: z.enum(['production', 'sandbox']).default('production'),
});

export async function pushTokenRoutes(app: FastifyInstance): Promise<void> {
  app.addHook('preHandler', requireAuth(app));

  // Register (or refresh) a device's APNs token.
  app.post('/', async (req) => {
    const { token, kind, environment } = registerBody.parse(req.body);
    const userId = (req as AuthedRequest).userId;

    await getPrisma().pushToken.upsert({
      where: { token },
      create: { userId, token, kind, environment, platform: 'ios' },
      update: { userId, kind, environment, lastSeenAt: new Date() },
    });
    return { ok: true };
  });

  // Unregister on sign-out.
  app.delete('/:token', async (req) => {
    const token = z.object({ token: z.string().min(1) }).parse(req.params).token;
    await getPrisma().pushToken.deleteMany({
      where: { token, userId: (req as AuthedRequest).userId },
    });
    return { ok: true };
  });
}
