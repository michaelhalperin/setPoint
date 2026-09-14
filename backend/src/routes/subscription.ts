import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { requireAuth, type AuthedRequest } from '../auth/index.js';
import { getPrisma } from '../db/client.js';
import { captureError } from '../observability/sentry.js';
import {
  SubscriptionVerificationError,
  verifyNotification,
  verifyTransaction,
} from '../subscription/entitlement.js';
import {
  applySubscriptionNotification,
  saveVerifiedSubscription,
  SubscriptionOwnedElsewhereError,
  subscriptionView,
} from '../subscription/store.js';

const verifyBody = z.object({
  transactionJws: z.string().min(20).max(20_000),
});

const notificationBody = z.object({
  signedPayload: z.string().min(20).max(100_000),
});

export async function subscriptionRoutes(app: FastifyInstance): Promise<void> {
  const authed = { preHandler: requireAuth(app) };

  app.get('/', authed, async (req) => {
    const user = await getPrisma().user.findUnique({
      where: { id: (req as AuthedRequest).userId },
      select: {
        id: true,
        subscriptionStatus: true,
        subscriptionExpiresAt: true,
        subscriptionProductId: true,
        subscriptionOriginalTransactionId: true,
      },
    });
    if (!user) throw app.httpErrors.notFound('user not found');
    return subscriptionView(user);
  });

  // The app sends the Apple-signed transaction after a purchase, a restore, or a renewal it saw.
  app.post('/verify', authed, async (req) => {
    const { transactionJws } = verifyBody.parse(req.body);
    let verified;
    try {
      verified = await verifyTransaction(transactionJws);
    } catch (err) {
      if (err instanceof SubscriptionVerificationError) {
        req.log.warn({ reason: err.message }, 'subscription verify rejected');
        throw app.httpErrors.badRequest('could not verify that App Store transaction');
      }
      throw err;
    }
    try {
      return await saveVerifiedSubscription(getPrisma(), (req as AuthedRequest).userId, verified);
    } catch (err) {
      if (err instanceof SubscriptionOwnedElsewhereError) throw app.httpErrors.conflict(err.message);
      throw err;
    }
  });

  // App Store Server Notifications V2 — renewals, expiries, refunds. Set this URL in App Store Connect.
  // Unauthenticated: trust comes from Apple's signature, which is verified before anything is stored.
  app.post('/apple-notifications', async (req, reply) => {
    const { signedPayload } = notificationBody.parse(req.body);
    try {
      const { subscription } = await verifyNotification(signedPayload);
      if (subscription) await applySubscriptionNotification(getPrisma(), subscription);
    } catch (err) {
      if (err instanceof SubscriptionVerificationError) {
        req.log.warn({ reason: err.message }, 'apple notification rejected');
        throw app.httpErrors.badRequest('could not verify that notification');
      }
      captureError(err, { tags: { route: 'apple-notifications' } });
      throw err;
    }
    return reply.code(200).send({ ok: true });
  });
}
