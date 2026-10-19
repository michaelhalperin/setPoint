import type { PrismaClient } from '@prisma/client';
import { describe, expect, it } from 'vitest';
import { startCheckIn } from './startCheckIn.js';

type AnyRow = Record<string, unknown>;

function fakePrisma(opts: {
  checkIns?: AnyRow[];
  user?: AnyRow | null;
} = {}) {
  const checkIns = opts.checkIns ?? [];
  const prisma = {
    __tables: { checkIns },
    checkIn: {
      findFirst: async ({ where }: { where: AnyRow }) => {
        return (
          checkIns.find((row) => {
            if (row.userId !== where.userId) return false;
            const statuses = (where.status as { in?: string[] } | undefined)?.in;
            if (statuses && !statuses.includes(row.status as string)) return false;
            const tier = where.tier as { lt?: number } | undefined;
            if (tier?.lt != null && !((row.tier as number) < tier.lt)) return false;
            if (where.prescription && row.prescription == null) return false;
            return true;
          }) ?? null
        );
      },
      create: async ({ data }: { data: AnyRow }) => {
        const row = { id: 'ci_new', ...data };
        checkIns.push(row);
        return row;
      },
    },
    user: {
      findUnique: async () => opts.user ?? null,
    },
    meal: {
      findMany: async () => [],
    },
  };
  return prisma as unknown as PrismaClient & { __tables: { checkIns: AnyRow[] } };
}

describe('startCheckIn', () => {
  it('reuses an open meal check-in that already has a prescription', async () => {
    const prisma = fakePrisma({
      checkIns: [{ id: 'ci_open', userId: 'u1', status: 'PENDING', tier: 2, prescription: { id: 'rx_1' } }],
    });
    await expect(startCheckIn(prisma, 'u1')).resolves.toEqual({ checkInId: 'ci_open' });
  });

  it('rejects when the user has not onboarded', async () => {
    const prisma = fakePrisma({ user: { timezone: 'UTC', onboarding: null } });
    await expect(startCheckIn(prisma, 'u1')).rejects.toMatchObject({
      message: 'onboarding required',
      statusCode: 409,
    });
  });
});
