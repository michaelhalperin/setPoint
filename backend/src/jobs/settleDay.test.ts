import type { PrismaClient } from '@prisma/client';
import { describe, expect, it, vi } from 'vitest';
import type { ManagerVoice } from '../managerVoice/types.js';
import { runSettleDayJob } from './settleDay.js';

// 2026-09-02T06:00:00Z is 02:00 in New York → "yesterday" is 2026-09-01.
const NOW = new Date('2026-09-02T06:00:00Z');

const voice: ManagerVoice = {
  checkInMessage: vi.fn(async () => 'ci'),
  homeNote: vi.fn(async () => 'note'),
  daySummary: vi.fn(async (ctx) => `summary:${ctx.kind}`),
};

type AnyRow = Record<string, unknown>;

function fakePrisma(users: AnyRow[], mealsByUser: Record<string, AnyRow[]>) {
  const outcomes: AnyRow[] = [];
  return {
    __outcomes: outcomes,
    user: { findMany: async () => users },
    meal: {
      findMany: async ({ where }: { where: AnyRow }) => {
        const uid = where.userId as string;
        const range = where.loggedAt as { gte: Date; lt: Date };
        return (mealsByUser[uid] ?? []).filter(
          (m) => (m.loggedAt as Date) >= range.gte && (m.loggedAt as Date) < range.lt,
        );
      },
    },
    dayOutcome: {
      upsert: async ({ where, create, update }: { where: AnyRow; create: AnyRow; update: AnyRow }) => {
        const key = where.userId_date as { userId: string; date: Date };
        const existing = outcomes.find(
          (o) => o.userId === key.userId && (o.date as Date).getTime() === key.date.getTime(),
        );
        if (existing) {
          Object.assign(existing, update);
          return existing;
        }
        const row = { ...create };
        outcomes.push(row);
        return row;
      },
    },
  } as unknown as PrismaClient & { __outcomes: AnyRow[] };
}

const user = (id: string): AnyRow => ({
  id,
  timezone: 'America/New_York',
  onboarding: { goal: 'BULK', dailyKcalTarget: 3000, completedAt: new Date('2026-01-01') },
});

const ymd = (d: Date) => new Date(d.getTime() - 8 * 3_600_000); // helper: a time on 2026-09-01 NY

describe('runSettleDayJob', () => {
  it('writes one DayOutcome per user for the previous local day', async () => {
    const prisma = fakePrisma([user('a'), user('b')], {
      // user a ate well on Sep 1 (NY)
      a: [
        { loggedAt: new Date('2026-09-01T16:00:00Z'), kcal: 1500 },
        { loggedAt: new Date('2026-09-01T23:00:00Z'), kcal: 1400 },
      ],
      // user b logged nothing
      b: [],
    });

    const summary = await runSettleDayJob({ prisma, voice, now: NOW });

    expect(summary.outcomesWritten).toBe(2);
    expect(summary.byKind).toEqual({ ON_TRACK: 1, MISSED: 1 });

    const a = prisma.__outcomes.find((o) => o.userId === 'a');
    expect(a).toMatchObject({ kind: 'ON_TRACK', kcalConsumed: 2900, kcalTarget: 3000, summaryLine: 'summary:ON_TRACK' });
    expect((a?.date as Date).toISOString().slice(0, 10)).toBe('2026-09-01');

    const b = prisma.__outcomes.find((o) => o.userId === 'b');
    expect(b).toMatchObject({ kind: 'MISSED', kcalConsumed: 0 });
  });

  it('is idempotent — re-running upserts the same row', async () => {
    const prisma = fakePrisma([user('a')], { a: [{ loggedAt: new Date('2026-09-01T18:00:00Z'), kcal: 1000 }] });
    await runSettleDayJob({ prisma, voice, now: NOW });
    await runSettleDayJob({ prisma, voice, now: NOW });
    expect(prisma.__outcomes).toHaveLength(1);
    expect(prisma.__outcomes[0]).toMatchObject({ kind: 'UNDER' });
  });

  it('ignores meals outside the previous local day', async () => {
    const prisma = fakePrisma([user('a')], {
      a: [
        { loggedAt: new Date('2026-08-31T18:00:00Z'), kcal: 3000 }, // day before
        { loggedAt: new Date('2026-09-02T05:00:00Z'), kcal: 3000 }, // today (NY: Sep 1 23:00? no — Sep 2 01:00)
        { loggedAt: new Date('2026-09-01T20:00:00Z'), kcal: 1200 }, // in-window
      ],
    });
    void ymd;
    await runSettleDayJob({ prisma, voice, now: NOW });
    expect(prisma.__outcomes[0]).toMatchObject({ kcalConsumed: 1200 });
  });
});
