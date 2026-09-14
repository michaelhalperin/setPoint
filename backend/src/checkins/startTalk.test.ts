import type { PrismaClient } from '@prisma/client';
import { describe, expect, it } from 'vitest';
import { startTalk } from './startTalk.js';

type AnyRow = Record<string, unknown>;

function fakePrisma(conversations: AnyRow[] = [], checkIns: AnyRow[] = []) {
  let seq = 0;
  const prisma = {
    __tables: { conversations, checkIns },
    escalationConversation: {
      findFirst: async ({ where }: { where: AnyRow }) =>
        conversations.find((row) => {
          if (row.userId !== where.userId) return false;
          if (row.resolvedAt !== where.resolvedAt) return false;
          if (where.checkInId && typeof where.checkInId === 'object' && 'not' in where.checkInId) {
            return row.checkInId !== (where.checkInId as { not: unknown }).not;
          }
          return true;
        }) ?? null,
      create: async ({ data }: { data: AnyRow }) => {
        const row = { id: `ec_${(seq += 1)}`, resolvedAt: null, ...data };
        conversations.push(row);
        return row;
      },
    },
    checkIn: {
      create: async ({ data }: { data: AnyRow }) => {
        const row = { id: `ci_${(seq += 1)}`, ...data };
        checkIns.push(row);
        return row;
      },
    },
  };
  return prisma as unknown as PrismaClient & { __tables: { conversations: AnyRow[]; checkIns: AnyRow[] } };
}

describe('startTalk', () => {
  it('reuses an unresolved conversation', async () => {
    const prisma = fakePrisma([{ userId: 'u1', checkInId: 'ci_open', resolvedAt: null }]);
    await expect(startTalk(prisma, 'u1')).resolves.toEqual({ checkInId: 'ci_open' });
    expect(prisma.__tables.checkIns).toHaveLength(0);
  });

  it('skips a resolved conversation and opens a new one', async () => {
    const prisma = fakePrisma([{ userId: 'u1', checkInId: 'ci_old', resolvedAt: new Date() }]);
    await expect(startTalk(prisma, 'u1')).resolves.toEqual({ checkInId: 'ci_1' });
    expect(prisma.__tables.checkIns[0]).toMatchObject({ userId: 'u1', tier: 3, status: 'PENDING' });
    expect(prisma.__tables.conversations).toHaveLength(2);
    expect(prisma.__tables.conversations[1]).toMatchObject({ userId: 'u1', checkInId: 'ci_1' });
  });

  it('opens a new conversation when none exist', async () => {
    const prisma = fakePrisma();
    await expect(startTalk(prisma, 'u1')).resolves.toEqual({ checkInId: 'ci_1' });
  });
});
