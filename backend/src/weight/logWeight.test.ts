import type { PrismaClient } from '@prisma/client';
import { describe, expect, it } from 'vitest';
import { InvalidWeightError, logWeight } from './logWeight.js';

type AnyRow = Record<string, unknown>;

function fakePrisma(profile: AnyRow | null) {
  const entries: AnyRow[] = [];
  const state = { profile };
  const prisma = {
    __state: state,
    __entries: entries,
    onboardingProfile: {
      findUnique: async () => state.profile,
      update: async ({ data }: { data: AnyRow }) => {
        if (state.profile) Object.assign(state.profile, data);
        return state.profile;
      },
    },
    weightEntry: {
      upsert: async ({ create }: { create: AnyRow }) => {
        const row = { id: `w${entries.length + 1}`, ...create };
        entries.push(row);
        return row;
      },
    },
  };
  return prisma as unknown as PrismaClient & { __state: typeof state; __entries: AnyRow[] };
}

const dietProfile = (): AnyRow => ({
  goal: 'DIET',
  sex: 'MALE',
  birthDate: new Date('1994-05-01'),
  heightCm: 180,
  weightKg: 80,
  activityLevel: 'MODERATE',
  startWeightKg: 80,
  targetWeightKg: 74,
  paceKgPerWeek: 0.5,
  goalStartedAt: new Date('2026-08-01T00:00:00Z'),
  dailyKcalTarget: 2200,
  dailyProteinTargetG: 160,
});

const NOW = new Date('2026-09-15T12:00:00Z');

describe('logWeight', () => {
  it('records an entry and returns mid-goal progress', async () => {
    const prisma = fakePrisma(dietProfile());
    const res = await logWeight({ prisma, now: NOW }, 'u1', { weightKg: 77.4 });
    expect(prisma.__entries).toHaveLength(1);
    expect(res.goalReached).toBe(false);
    expect(res.goal).toBe('DIET');
    expect(res.progress?.remainingKg).toBeCloseTo(3.4, 1);
  });

  it('flips to MAINTAIN and recomputes targets when the goal is reached', async () => {
    const prisma = fakePrisma(dietProfile());
    const res = await logWeight({ prisma, now: NOW }, 'u1', { weightKg: 73.8 });
    expect(res.goalReached).toBe(true);
    expect(res.goal).toBe('MAINTAIN');
    expect(res.progress).toBeNull();
    expect(prisma.__state.profile).toMatchObject({ goal: 'MAINTAIN', paceKgPerWeek: 0 });
    // maintenance target has no deficit, so it's above the old diet target
    expect(res.dailyKcalTarget).toBeGreaterThan(2200);
  });

  it('rejects an absurd weight', async () => {
    const prisma = fakePrisma(dietProfile());
    await expect(logWeight({ prisma, now: NOW }, 'u1', { weightKg: 5 })).rejects.toBeInstanceOf(InvalidWeightError);
  });
});
