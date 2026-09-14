import type { PrismaClient } from '@prisma/client';
import { appAccountTokenFor, isEntitled, type VerifiedSubscription } from './entitlement.js';

export class SubscriptionOwnedElsewhereError extends Error {}

const SELECT = {
  id: true,
  subscriptionStatus: true,
  subscriptionExpiresAt: true,
  subscriptionProductId: true,
  subscriptionOriginalTransactionId: true,
} as const;

type SubscriptionRow = {
  id: string;
  subscriptionStatus: string | null;
  subscriptionExpiresAt: Date | null;
  subscriptionProductId: string | null;
  subscriptionOriginalTransactionId: string | null;
};

export type SubscriptionView = {
  entitled: boolean;
  status: string | null;
  expiresAt: string | null;
  productId: string | null;
  appAccountToken: string;
};

export function subscriptionView(row: SubscriptionRow, now = new Date()): SubscriptionView {
  return {
    entitled: isEntitled(row, now),
    status: row.subscriptionStatus,
    expiresAt: row.subscriptionExpiresAt?.toISOString() ?? null,
    productId: row.subscriptionProductId,
    appAccountToken: appAccountTokenFor(row.id),
  };
}

/**
 * Stores a verified transaction on the account that owns it. A subscription belongs to
 * one SetPoint account: bought by another account (appAccountToken) or already linked
 * to one (originalTransactionId) → SubscriptionOwnedElsewhereError. An older transaction
 * never rolls a later expiry back, except a refund/revocation.
 */
export async function saveVerifiedSubscription(
  prisma: Pick<PrismaClient, 'user'>,
  userId: string,
  sub: VerifiedSubscription,
  now = new Date(),
): Promise<SubscriptionView> {
  if (sub.appAccountToken && sub.appAccountToken.toLowerCase() !== appAccountTokenFor(userId)) {
    throw new SubscriptionOwnedElsewhereError('this subscription was bought by another SetPoint account');
  }
  const owner = await prisma.user.findUnique({
    where: { subscriptionOriginalTransactionId: sub.originalTransactionId },
    select: { id: true },
  });
  if (owner && owner.id !== userId) {
    throw new SubscriptionOwnedElsewhereError('this subscription is linked to another SetPoint account');
  }
  const current = await prisma.user.findUnique({ where: { id: userId }, select: SELECT });
  if (!current) throw new Error('user not found');
  const row = shouldApply(current, sub)
    ? await prisma.user.update({
        where: { id: userId },
        data: {
          subscriptionStatus: sub.status,
          subscriptionExpiresAt: sub.expiresAt,
          subscriptionProductId: sub.productId,
          subscriptionOriginalTransactionId: sub.originalTransactionId,
          subscriptionEnvironment: sub.environment,
        },
        select: SELECT,
      })
    : current;
  return subscriptionView(row, now);
}

/** Applies a verified App Store Server Notification to whichever account owns the subscription. */
export async function applySubscriptionNotification(
  prisma: Pick<PrismaClient, 'user'>,
  sub: VerifiedSubscription,
): Promise<boolean> {
  const owner = await prisma.user.findUnique({
    where: { subscriptionOriginalTransactionId: sub.originalTransactionId },
    select: SELECT,
  });
  if (!owner || !shouldApply(owner, sub)) return false;
  await prisma.user.update({
    where: { id: owner.id },
    data: {
      subscriptionStatus: sub.status,
      subscriptionExpiresAt: sub.expiresAt,
      subscriptionProductId: sub.productId,
      subscriptionEnvironment: sub.environment,
    },
  });
  return true;
}

function shouldApply(current: SubscriptionRow, sub: VerifiedSubscription): boolean {
  if (sub.status === 'REVOKED') return true;
  if (current.subscriptionOriginalTransactionId !== sub.originalTransactionId) return true;
  const stored = current.subscriptionExpiresAt?.getTime() ?? 0;
  return sub.expiresAt.getTime() >= stored;
}
