import type { PrismaClient } from '@prisma/client';
import { revokeAppleToken } from '../auth/appleRevoke.js';
import { captureError } from '../observability/sentry.js';
import type { PhotoStore } from '../photos/store.js';

export class AccountNotFoundError extends Error {}

export type DeleteAccountResult = {
  deleted: true;
  appleTokenRevoked: boolean;
};

/**
 * Deletes a user and everything keyed to them (plan §4). Every `userId` FK in
 * the schema is `onDelete: Cascade`, so `user.delete` cascades across
 * onboarding, screening, meals, check-ins, prescriptions, confidence scores,
 * biosignals, day outcomes, AI usage and push tokens in one statement. Meal
 * photos live outside Postgres, so they're removed from object storage too.
 *
 * Best-effort around the edges: an Apple revoke or photo-storage failure must
 * not block the deletion Apple requires us to honour — it's logged and reported.
 */
export async function deleteAccount(
  deps: { prisma: PrismaClient; photos?: PhotoStore | null },
  userId: string,
): Promise<DeleteAccountResult> {
  const user = await deps.prisma.user.findUnique({
    where: { id: userId },
    select: { id: true, appleRefreshToken: true },
  });
  if (!user) throw new AccountNotFoundError('account not found');

  let appleTokenRevoked = false;
  if (user.appleRefreshToken) {
    try {
      await revokeAppleToken(user.appleRefreshToken);
      appleTokenRevoked = true;
    } catch (err) {
      console.error(`[account] Apple token revocation failed for ${userId}`, err);
    }
  }

  await deps.prisma.user.delete({ where: { id: userId } });

  if (deps.photos) {
    try {
      await deps.photos.deleteAllForUser(userId);
    } catch (err) {
      // Orphaned photos after a deletion must be cleaned up by hand — make it loud.
      console.error(`[account] photo deletion failed for ${userId}`, err);
      captureError(err, { userId, tags: { area: 'account-delete-photos' } });
    }
  }

  return { deleted: true, appleTokenRevoked };
}
