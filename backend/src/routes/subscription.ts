import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { requireAuth, type AuthedRequest } from '../auth/index.js';
import { getPrisma } from '../db/client.js';
import { isEntitled, subscriptionFromJws } from '../subscription/entitlement.js';

const verifyBody = z.object({
  transactionJws: z.string().min(20).max(20_000),
});

export async function subscriptionRoutes(app: FastifyInstance): Promise<void> {
  app.addHook('preHandler', requireAuth(app));

  app.get('/', async (req) => {
    const user = await getPrisma().user.findUnique({
      where: { id: (req as AuthedRequest).userId },
      select: { subscriptionStatus: true, subscriptionExpiresAt: true, subscriptionProductId: true },
    });
    if (!user) throw app.httpErrors.notFound('user not found');
    return {
      entitled: isEntitled(user),
      status: user.subscriptionStatus,
      expiresAt: user.subscriptionExpiresAt?.toISOString() ?? null,
      productId: user.subscriptionProductId,
    };
  });

  app.post('/verify', async (req) => {
    const { transactionJws } = verifyBody.parse(req.body);
    let parsed;
    try {
      parsed = subscriptionFromJws(transactionJws);
    } catch {
      throw app.httpErrors.badRequest('could not read that App Store transaction');
    }
    const userId = (req as AuthedRequest).userId;
    const user = await getPrisma().user.update({
      where: { id: userId },
      data: {
        subscriptionStatus: parsed.status,
        subscriptionExpiresAt: parsed.expiresAt,
        subscriptionProductId: parsed.productId,
      },
      select: { subscriptionStatus: true, subscriptionExpiresAt: true, subscriptionProductId: true },
    });
    return {
      entitled: isEntitled(user),
      status: user.subscriptionStatus,
      expiresAt: user.subscriptionExpiresAt?.toISOString() ?? null,
      productId: user.subscriptionProductId,
    };
  });
}
