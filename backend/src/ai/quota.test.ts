import type { PrismaClient } from '@prisma/client';
import { describe, expect, it } from 'vitest';
import { AI_QUOTAS, AiQuotaExceededError, consumeAiQuota, evaluateQuota } from './quota.js';

const MIN = 60_000;
const HOUR = 60 * MIN;

describe('evaluateQuota', () => {
  const limits = [
    { windowMs: HOUR, max: 3 },
    { windowMs: 24 * HOUR, max: 5 },
  ];
  const now = 10 * 24 * HOUR;

  it('allows a call under every limit', () => {
    expect(evaluateQuota([now - MIN, now - 2 * MIN], limits, now)).toEqual({ allowed: true });
  });

  it('blocks at the hourly cap and says when the oldest call ages out', () => {
    const used = [now - 50 * MIN, now - 20 * MIN, now - 5 * MIN];
    expect(evaluateQuota(used, limits, now)).toEqual({ allowed: false, retryAfterSeconds: 10 * 60 });
  });

  it('ignores calls that have left the window', () => {
    const used = [now - 2 * HOUR, now - 3 * HOUR, now - 4 * HOUR];
    expect(evaluateQuota(used, limits, now)).toEqual({ allowed: true });
  });

  it('blocks on the daily cap even when the last hour is quiet', () => {
    const used = [now - 23 * HOUR, now - 20 * HOUR, now - 10 * HOUR, now - 5 * HOUR, now - 2 * HOUR];
    // The call from 23 h ago frees a slot in 1 h.
    expect(evaluateQuota(used, limits, now)).toEqual({ allowed: false, retryAfterSeconds: 60 * 60 });
  });
});

type UsageRow = { userId: string; kind: string; createdAt: Date };

function fakePrisma() {
  const rows: UsageRow[] = [];
  return {
    rows,
    aiUsage: {
      findMany: async ({ where }: { where: { userId: string; kind: string; createdAt: { gt: Date } } }) =>
        rows.filter((r) => r.userId === where.userId && r.kind === where.kind && r.createdAt > where.createdAt.gt),
      create: async ({ data }: { data: UsageRow }) => {
        rows.push(data);
        return data;
      },
    },
  };
}

describe('consumeAiQuota', () => {
  it('records calls up to the limit, then refuses without recording', async () => {
    const prisma = fakePrisma();
    const db = prisma as unknown as PrismaClient;
    const now = new Date('2026-09-10T12:00:00Z');
    const hourly = AI_QUOTAS.meal_parse[0]!.max;

    for (let i = 0; i < hourly; i += 1) await consumeAiQuota(db, 'u1', 'meal_parse', now);

    const refused = consumeAiQuota(db, 'u1', 'meal_parse', now);
    await expect(refused).rejects.toBeInstanceOf(AiQuotaExceededError);
    await expect(refused).rejects.toMatchObject({ retryAfterSeconds: 3600 });
    expect(prisma.rows).toHaveLength(hourly);
  });

  it('keeps users and kinds separate', async () => {
    const prisma = fakePrisma();
    const db = prisma as unknown as PrismaClient;
    const now = new Date('2026-09-10T12:00:00Z');
    for (let i = 0; i < AI_QUOTAS.meal_parse[0]!.max; i += 1) await consumeAiQuota(db, 'u1', 'meal_parse', now);

    await expect(consumeAiQuota(db, 'u2', 'meal_parse', now)).resolves.toBeUndefined();
    await expect(consumeAiQuota(db, 'u1', 'tier3_message', now)).resolves.toBeUndefined();
  });
});
