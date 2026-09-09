import type { PrismaClient } from '@prisma/client';
import { revokeAppleToken } from '../auth/appleRevoke.js';

export class AccountNotFoundError extends Error {}

export type DeleteAccountResult = {
  deleted: true;
  appleTokenRevoked: boolean;
};

/**
 * Deletes a user and everything keyed to them (plan §4). Every `userId` FK in
 * the schema is `onDelete: Cascade`, so `user.delete` cascades across
 * onboarding, screening, meals, check-ins, prescriptions, confidence scores,
 * biosignals, day outcomes and push tokens in one statement.
 *
 * Best-effort: revoke the Sign in with Apple refresh token first (a failure
 * there must not block the deletion Apple requires us to honour).
 */
export async function deleteAccount(
  deps: { prisma: PrismaClient },
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

  return { deleted: true, appleTokenRevoked };
}
