import { describe, expect, it } from 'vitest';
import { LOCK_TTL_MS } from './kinds.js';
import { lockActive, recordTrip } from './lock.js';

describe('lockActive', () => {
  it('is false when unset or already expired', () => {
    const now = new Date('2026-10-21T12:00:00Z');
    expect(lockActive(null, now)).toBe(false);
    expect(lockActive(new Date('2026-10-21T11:00:00Z'), now)).toBe(false);
  });

  it('is true until the 48h auto-expire', () => {
    const now = new Date('2026-10-21T12:00:00Z');
    expect(lockActive(new Date(now.getTime() + LOCK_TTL_MS), now)).toBe(true);
  });
});

function fakePrisma() {
  const trips: { userId: string; createdAt: Date }[] = [];
  let lockedUntil: Date | null = null;
  return {
    trips,
    get lockedUntil() {
      return lockedUntil;
    },
    expertSafetyTrip: {
      create: async ({ data }: { data: { userId: string; createdAt: Date } }) => {
        trips.push({ userId: data.userId, createdAt: data.createdAt });
        return data;
      },
      findMany: async ({ where }: { where: { userId: string; createdAt: { gte: Date } } }) =>
        trips.filter((t) => t.userId === where.userId && t.createdAt >= where.createdAt.gte),
    },
    expertConversation: {
      update: async ({ data }: { data: { lockedUntil: Date } }) => {
        lockedUntil = data.lockedUntil;
        return data;
      },
    },
  };
}

describe('recordTrip', () => {
  it('locks after 2 trips in 24 hours, for 48 hours', async () => {
    const prisma = fakePrisma();
    const db = prisma as unknown as Parameters<typeof recordTrip>[0];
    const t0 = new Date('2026-10-21T12:00:00Z');
    const first = await recordTrip(db, {
      userId: 'u1',
      conversationId: 'c1',
      layer: 'input',
      code: 'restriction',
      now: t0,
    });
    expect(first.lockedUntil).toBeNull();
    const second = await recordTrip(db, {
      userId: 'u1',
      conversationId: 'c1',
      layer: 'input',
      code: 'restriction',
      now: new Date(t0.getTime() + 60 * 60_000),
    });
    expect(second.lockedUntil).not.toBeNull();
    expect(second.lockedUntil!.getTime() - (t0.getTime() + 60 * 60_000)).toBe(LOCK_TTL_MS);
  });

  it('locks after 3 trips in 7 days even if they are spread out', async () => {
    const prisma = fakePrisma();
    const db = prisma as unknown as Parameters<typeof recordTrip>[0];
    const t0 = new Date('2026-10-21T12:00:00Z');
    await recordTrip(db, { userId: 'u1', conversationId: 'c1', layer: 'input', code: 'ed', now: t0 });
    await recordTrip(db, {
      userId: 'u1',
      conversationId: 'c1',
      layer: 'input',
      code: 'ed',
      now: new Date(t0.getTime() + 2 * 86_400_000),
    });
    const third = await recordTrip(db, {
      userId: 'u1',
      conversationId: 'c1',
      layer: 'input',
      code: 'ed',
      now: new Date(t0.getTime() + 4 * 86_400_000),
    });
    expect(third.lockedUntil).not.toBeNull();
  });
});
