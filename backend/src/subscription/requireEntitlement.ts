import type { FastifyInstance } from 'fastify';
import { getPrisma } from '../db/client.js';
import { isFlagOnForUser } from '../flags/index.js';
import { isEntitled, subscriptionGateOn } from '../subscription/entitlement.js';

export async function requireEntitlement(app: FastifyInstance, userId: string): Promise<void> {
  if (!subscriptionGateOn()) return;
  if (!(await isFlagOnForUser(getPrisma(), userId, 'paywall'))) return;
  const user = await getPrisma().user.findUnique({
    where: { id: userId },
    select: { subscriptionStatus: true, subscriptionExpiresAt: true },
  });
  if (!user || !isEntitled(user)) {
    throw app.httpErrors.createError(402, 'subscription required');
  }
}
