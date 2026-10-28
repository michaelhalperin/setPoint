import { randomInt } from 'node:crypto';
import type { InviteCode, PrismaClient, UserRole } from '@prisma/client';

/**
 * Invite codes: while sign-up is invite-only, a new account is let in by
 * redeeming one. A code can put people in a group ("beta") and give them
 * a role, and can be capped in uses and time.
 */

/** No 0/O, 1/I/L — codes get read aloud and typed from a message. */
const ALPHABET = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';

export function generateInviteCode(length = 8): string {
  let code = '';
  for (let i = 0; i < length; i += 1) code += ALPHABET[randomInt(ALPHABET.length)];
  return code;
}

/** Case and spaces don't matter: "beta 2026" and "BETA2026" are the same code. */
export function normalizeInviteCode(raw: string): string {
  return raw.replace(/[\s-]+/g, '').toUpperCase();
}

export type InviteProblem = 'unknown' | 'disabled' | 'expired' | 'used_up';

/** Why a code can't be used right now, or null if it can. */
export function inviteProblem(
  invite: Pick<InviteCode, 'disabledAt' | 'expiresAt' | 'maxUses' | 'uses'> | null,
  now: Date = new Date(),
): InviteProblem | null {
  if (!invite) return 'unknown';
  if (invite.disabledAt) return 'disabled';
  if (invite.expiresAt && invite.expiresAt <= now) return 'expired';
  if (invite.maxUses !== null && invite.uses >= invite.maxUses) return 'used_up';
  return null;
}

const ROLE_RANK: Record<UserRole, number> = { USER: 0, TRAINER: 1, ADMIN: 2 };

/** A code can raise a role, never lower it — an admin redeeming a user code stays admin. */
export function higherRole(a: UserRole, b: UserRole): UserRole {
  return ROLE_RANK[a] >= ROLE_RANK[b] ? a : b;
}

export class InviteRejectedError extends Error {
  constructor(readonly problem: InviteProblem) {
    super(`invite ${problem}`);
  }
}

/**
 * Lets a user in with a code: counts the use, records the code, sets access, the
 * code's group, and its role if higher. The use is counted with a compare-and-set
 * on `uses`, so two people racing for the last use can't both get it.
 */
export async function redeemInvite(
  prisma: PrismaClient,
  userId: string,
  rawCode: string,
  now: Date = new Date(),
): Promise<{ group: string | null; role: UserRole }> {
  const code = normalizeInviteCode(rawCode);
  if (!code) throw new InviteRejectedError('unknown');

  return prisma.$transaction(async (tx) => {
    const invite = await tx.inviteCode.findUnique({ where: { code } });
    const problem = inviteProblem(invite, now);
    if (problem || !invite) throw new InviteRejectedError(problem ?? 'unknown');

    const counted = await tx.inviteCode.updateMany({
      where: { id: invite.id, uses: invite.uses },
      data: { uses: { increment: 1 } },
    });
    if (counted.count === 0) throw new InviteRejectedError('used_up');

    const user = await tx.user.findUniqueOrThrow({ where: { id: userId }, select: { role: true, group: true, accessGrantedAt: true } });
    const role = higherRole(user.role, invite.role);
    const group = invite.group ?? user.group;
    await tx.user.update({
      where: { id: userId },
      data: { accessGrantedAt: user.accessGrantedAt ?? now, inviteCodeId: invite.id, group, role },
    });
    return { group, role };
  });
}
