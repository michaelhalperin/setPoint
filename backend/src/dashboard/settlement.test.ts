import type { PrismaClient } from '@prisma/client';
import { describe, expect, it } from 'vitest';
import { buildSettlement } from './settlement.js';

const NOW = new Date('2026-09-15T18:00:00Z');
type AnyRow = Record<string, unknown>;

function fakePrisma(over: { onboarding?: AnyRow; weightEntries?: AnyRow[]; meals?: AnyRow[] } = {}) {
  const user: AnyRow = {
    id: 'u1',
    timezone: 'America/New_York',
    onboarding: over.onboarding ?? { goal: 'DIET', dailyKcalTarget: 2200 },
    weightEntries: over.weightEntries ?? [],
  };
  return {
    user: { findUnique: async () => user },
    dayOutcome: { findMany: async () => [] },
    meal: { findMany: async () => over.meals ?? [] },
  } as unknown as PrismaClient;
}

const dietGoal = {
  goal: 'DIET',
  dailyKcalTarget: 2200,
  startWeightKg: 82,
  targetWeightKg: 76,
  paceKgPerWeek: 0.5,
  goalStartedAt: new Date('2026-08-01T00:00:00Z'),
  weightKg: 82,
};

describe('buildSettlement weightGoal', () => {
  it('is null when the user has no weight goal', async () => {
    const view = await buildSettlement(
      { prisma: fakePrisma({ onboarding: { goal: 'MAINTAIN', dailyKcalTarget: 2500 } }), now: NOW },
      'u1',
    );
    expect(view.weightGoal).toBeNull();
  });

  it('reports progress and a stale weigh-in prompt', async () => {
    const view = await buildSettlement(
      {
        prisma: fakePrisma({
          onboarding: dietGoal,
          weightEntries: [{ weightKg: 79, measuredAt: new Date('2026-09-01T08:00:00Z') }],
        }),
        now: NOW,
      },
      'u1',
    );
    expect(view.weightGoal).toMatchObject({
      goal: 'DIET',
      startWeightKg: 82,
      targetWeightKg: 76,
      currentWeightKg: 79,
      remainingKg: 3,
      needsWeighIn: true, // last weigh-in > 7 days ago
    });
  });

  it('does not prompt when a recent weigh-in exists', async () => {
    const view = await buildSettlement(
      {
        prisma: fakePrisma({
          onboarding: dietGoal,
          weightEntries: [{ weightKg: 79, measuredAt: new Date('2026-09-14T08:00:00Z') }],
        }),
        now: NOW,
      },
      'u1',
    );
    expect(view.weightGoal?.needsWeighIn).toBe(false);
  });
});
