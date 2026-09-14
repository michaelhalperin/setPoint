import type { PrismaClient } from '@prisma/client';
import { describe, expect, it } from 'vitest';
import {
  acceptTargetReview,
  currentTargetSuggestion,
  dismissTargetReview,
  NoTargetReviewError,
  StaleTargetReviewError,
  undoLastTargetReview,
} from './targetReview.js';

const NOW = new Date('2026-08-22T09:00:00Z');
const STALLING = [
  { measuredAt: new Date('2026-08-01T08:00:00Z'), weightKg: 74 },
  { measuredAt: new Date('2026-08-08T08:00:00Z'), weightKg: 74.05 },
  { measuredAt: new Date('2026-08-15T08:00:00Z'), weightKg: 74.08 },
  { measuredAt: new Date('2026-08-22T08:00:00Z'), weightKg: 74.1 },
];

type Review = { id: string; status: string; previousKcal: number; proposedKcal: number; decidedAt: Date | null };

function fakeDb(opts: { enforcementEnabled?: boolean; kcal?: number } = {}) {
  const state = {
    profile: { goal: 'BULK', dailyKcalTarget: opts.kcal ?? 3000, paceKgPerWeek: 0.4 },
    reviews: [] as Review[],
  };
  const latest = (pred: (r: Review) => boolean) =>
    [...state.reviews].filter(pred).sort((a, b) => b.decidedAt!.getTime() - a.decidedAt!.getTime())[0] ?? null;
  const db = {
    user: {
      findUnique: async () => ({
        onboarding: state.profile,
        safetyScreening: { enforcementEnabled: opts.enforcementEnabled ?? true },
        weightEntries: STALLING,
      }),
    },
    weightTargetReview: {
      findFirst: async ({ where }: { where: { status?: string } }) =>
        latest((r) => r.decidedAt !== null && (!where.status || r.status === where.status)),
      create: async ({ data }: { data: Omit<Review, 'id'> }) => {
        const row = { ...data, id: `r${state.reviews.length + 1}` };
        state.reviews.push(row);
        return row;
      },
      update: async ({ where, data }: { where: { id: string }; data: Partial<Review> }) => {
        const row = state.reviews.find((r) => r.id === where.id)!;
        Object.assign(row, data);
        return row;
      },
    },
    onboardingProfile: {
      updateMany: async ({ where, data }: { where: { dailyKcalTarget: number }; data: { dailyKcalTarget: number } }) => {
        if (state.profile.dailyKcalTarget !== where.dailyKcalTarget) return { count: 0 };
        state.profile.dailyKcalTarget = data.dailyKcalTarget;
        return { count: 1 };
      },
    },
    $transaction: async (fn: (tx: unknown) => Promise<unknown>) => fn(db),
  };
  return { prisma: db as unknown as PrismaClient, state };
}

describe('target review', () => {
  it('suggests nothing in quiet mode', async () => {
    const { prisma } = fakeDb({ enforcementEnabled: false });
    expect(await currentTargetSuggestion(prisma, 'u1', NOW)).toBeNull();
  });

  it('accepts only the suggestion the server computed', async () => {
    const { prisma, state } = fakeDb();
    const s = (await currentTargetSuggestion(prisma, 'u1', NOW))!;
    await expect(acceptTargetReview(prisma, 'u1', 800, NOW)).rejects.toBeInstanceOf(StaleTargetReviewError);
    expect(state.profile.dailyKcalTarget).toBe(3000);

    const applied = await acceptTargetReview(prisma, 'u1', s.proposedKcal, NOW);
    expect(applied.dailyKcalTarget).toBe(s.proposedKcal);
    expect(state.profile.dailyKcalTarget).toBe(s.proposedKcal);
  });

  it('does not offer another change right after accepting', async () => {
    const { prisma } = fakeDb();
    const s = (await currentTargetSuggestion(prisma, 'u1', NOW))!;
    await acceptTargetReview(prisma, 'u1', s.proposedKcal, NOW);
    expect(await currentTargetSuggestion(prisma, 'u1', NOW)).toBeNull();
    await expect(acceptTargetReview(prisma, 'u1', s.proposedKcal + 100, NOW)).rejects.toBeInstanceOf(
      NoTargetReviewError,
    );
  });

  it('"not now" starts the cooldown without changing the target', async () => {
    const { prisma, state } = fakeDb();
    await dismissTargetReview(prisma, 'u1', NOW);
    expect(state.profile.dailyKcalTarget).toBe(3000);
    expect(state.reviews[0]?.status).toBe('REJECTED');
    expect(await currentTargetSuggestion(prisma, 'u1', NOW)).toBeNull();
  });

  it('undo restores the previous target, but not over a later manual edit', async () => {
    const { prisma, state } = fakeDb();
    const s = (await currentTargetSuggestion(prisma, 'u1', NOW))!;
    await acceptTargetReview(prisma, 'u1', s.proposedKcal, NOW);

    state.profile.dailyKcalTarget = 3400; // edited in Goal settings
    await expect(undoLastTargetReview(prisma, 'u1', NOW)).rejects.toBeInstanceOf(StaleTargetReviewError);

    state.profile.dailyKcalTarget = s.proposedKcal;
    expect((await undoLastTargetReview(prisma, 'u1', NOW)).dailyKcalTarget).toBe(3000);
    expect(state.reviews[0]?.status).toBe('UNDONE');
  });
});
