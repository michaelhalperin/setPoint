import type { PrismaClient } from '@prisma/client';
import { describe, expect, it, vi } from 'vitest';
import { AccountNotFoundError, deleteAccount } from './deleteAccount.js';

const revokeMock = vi.hoisted(() => vi.fn());
vi.mock('../auth/appleRevoke.js', () => ({ revokeAppleToken: revokeMock }));

type AnyRow = Record<string, unknown>;

function fakePrisma(users: AnyRow[]) {
  return {
    __users: users,
    user: {
      findUnique: async ({ where }: { where: AnyRow }) => users.find((u) => u.id === where.id) ?? null,
      delete: async ({ where }: { where: AnyRow }) => {
        const i = users.findIndex((u) => u.id === where.id);
        if (i >= 0) return users.splice(i, 1)[0];
        throw new Error('not found');
      },
    },
  } as unknown as PrismaClient & { __users: AnyRow[] };
}

describe('deleteAccount', () => {
  it('deletes the user (cascades) and reports no Apple revoke when none is stored', async () => {
    revokeMock.mockReset();
    const prisma = fakePrisma([{ id: 'u1', appleRefreshToken: null }]);

    const result = await deleteAccount({ prisma }, 'u1');

    expect(result).toEqual({ deleted: true, appleTokenRevoked: false });
    expect(prisma.__users).toHaveLength(0);
    expect(revokeMock).not.toHaveBeenCalled();
  });

  it('revokes the Apple refresh token when present', async () => {
    revokeMock.mockReset().mockResolvedValue(undefined);
    const prisma = fakePrisma([{ id: 'u1', appleRefreshToken: 'rt_123' }]);

    const result = await deleteAccount({ prisma }, 'u1');

    expect(revokeMock).toHaveBeenCalledWith('rt_123');
    expect(result.appleTokenRevoked).toBe(true);
  });

  it('still deletes the account when Apple revocation fails', async () => {
    revokeMock.mockReset().mockRejectedValue(new Error('apple down'));
    const prisma = fakePrisma([{ id: 'u1', appleRefreshToken: 'rt_123' }]);

    const result = await deleteAccount({ prisma }, 'u1');

    expect(result).toEqual({ deleted: true, appleTokenRevoked: false });
    expect(prisma.__users).toHaveLength(0);
  });

  it('throws when the account does not exist', async () => {
    await expect(deleteAccount({ prisma: fakePrisma([]) }, 'ghost')).rejects.toBeInstanceOf(AccountNotFoundError);
  });
});
