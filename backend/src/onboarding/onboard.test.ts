import type { PrismaClient } from '@prisma/client';
import { describe, expect, it } from 'vitest';
import { AlreadyOnboardedError, MissingTargetError, runOnboarding, type OnboardingInput } from './onboard.js';

type AnyRow = Record<string, unknown>;

function fakePrisma(seed: { onboarding?: AnyRow } = {}) {
  const store = {
    onboardingProfile: seed.onboarding ? [{ userId: 'u1', ...seed.onboarding }] : ([] as AnyRow[]),
    safetyScreening: [] as AnyRow[],
    dietaryRestriction: [] as AnyRow[],
    escalationState: [] as AnyRow[],
    weightEntry: [] as AnyRow[],
    user: [{ id: 'u1', timezone: 'UTC' }] as AnyRow[],
  };

  const coll = (rows: AnyRow[], key: 'userId' | 'id') => ({
    findUnique: async ({ where }: { where: AnyRow }) => rows.find((r) => r[key] === where[key]) ?? null,
    update: async ({ where, data }: { where: AnyRow; data: AnyRow }) => {
      const row = rows.find((r) => r[key] === where[key]);
      if (row) Object.assign(row, data);
      return row;
    },
    upsert: async ({ where, create, update }: { where: AnyRow; create: AnyRow; update: AnyRow }) => {
      const row = rows.find((r) => r[key] === where[key]);
      if (row) {
        Object.assign(row, update);
        return row;
      }
      const created = { ...where, ...create };
      rows.push(created);
      return created;
    },
    deleteMany: async ({ where }: { where: AnyRow }) => {
      const before = rows.length;
      for (let i = rows.length - 1; i >= 0; i -= 1) if (rows[i]![key] === where[key]) rows.splice(i, 1);
      return { count: before - rows.length };
    },
    createMany: async ({ data }: { data: AnyRow[] }) => {
      rows.push(...data);
      return { count: data.length };
    },
  });

  const prisma = {
    __store: store,
    onboardingProfile: coll(store.onboardingProfile, 'userId'),
    safetyScreening: coll(store.safetyScreening, 'userId'),
    dietaryRestriction: coll(store.dietaryRestriction, 'userId'),
    escalationState: coll(store.escalationState, 'userId'),
    user: coll(store.user, 'id'),
    weightEntry: {
      upsert: async ({ create }: { create: AnyRow }) => {
        store.weightEntry.push(create);
        return create;
      },
    },
    $transaction: async (fn: (tx: unknown) => Promise<unknown>) => fn(prisma),
  };
  return prisma as unknown as PrismaClient & { __store: typeof store };
}

const NOW = new Date('2026-09-10T12:00:00Z');

const baseInput = (over: Partial<OnboardingInput> = {}): OnboardingInput => ({
  goal: 'BULK',
  mode: 'SMART',
  sex: 'MALE',
  birthDate: '1994-05-01',
  heightCm: 180,
  weightKg: 78,
  activityLevel: 'MODERATE',
  safety: {
    medicalSupervisionRequired: false,
    scoff: {
      makeSelfSick: false,
      lostControl: false,
      lostOneStone: false,
      believesFat: false,
      foodDominates: false,
    },
    restrictions: [{ label: 'Peanuts' }, { label: 'peanut' }, { label: 'Shellfish', source: 'ALLERGY' }],
  },
  ...over,
});

describe('runOnboarding', () => {
  it('computes targets from stats, writes the profile, screening and restrictions', async () => {
    const prisma = fakePrisma();
    const result = await runOnboarding({ prisma, now: NOW }, 'u1', baseInput());

    expect(result.dailyKcalTarget).toBeGreaterThan(2800);
    expect(result.dailyProteinTargetG).toBe(Math.round(78 * 1.8));
    expect(result.enforcementEnabled).toBe(true);

    expect(prisma.__store.onboardingProfile[0]).toMatchObject({ goal: 'BULK', completedAt: NOW });
    expect(prisma.__store.safetyScreening[0]).toMatchObject({ scoffScore: 0, scoffFlagged: false });
    // "Peanuts" and "peanut" dedupe to one token
    expect(prisma.__store.dietaryRestriction.map((r) => r.token).sort()).toEqual(['peanut', 'shellfish']);
    expect(prisma.__store.escalationState).toHaveLength(1);
  });

  it('disables enforcement on a positive SCOFF screen', async () => {
    const prisma = fakePrisma();
    const result = await runOnboarding({ prisma, now: NOW }, 'u1', baseInput({
      safety: {
        medicalSupervisionRequired: false,
        scoff: {
          makeSelfSick: true,
          lostControl: true,
          lostOneStone: false,
          believesFat: false,
          foodDominates: false,
        },
      },
    }));
    expect(result.enforcementEnabled).toBe(false);
    expect(result.enforcementDisabledReason).toBe('EATING_DISORDER_SCREEN');
    expect(prisma.__store.safetyScreening[0]).toMatchObject({ enforcementEnabled: false });
  });

  it('requires an explicit target when body stats are missing', async () => {
    const prisma = fakePrisma();
    await expect(
      runOnboarding({ prisma, now: NOW }, 'u1', baseInput({ weightKg: undefined, heightCm: undefined, birthDate: undefined })),
    ).rejects.toBeInstanceOf(MissingTargetError);
  });

  it('accepts an explicit target with no stats', async () => {
    const prisma = fakePrisma();
    const result = await runOnboarding({ prisma, now: NOW }, 'u1', baseInput({
      weightKg: undefined,
      heightCm: undefined,
      birthDate: undefined,
      dailyKcalTarget: 2600,
    }));
    expect(result.dailyKcalTarget).toBe(2600);
    expect(result.dailyProteinTargetG).toBeNull();
  });

  it('rejects a second onboarding', async () => {
    const prisma = fakePrisma({ onboarding: { completedAt: new Date('2026-01-01') } });
    await expect(runOnboarding({ prisma, now: NOW }, 'u1', baseInput())).rejects.toBeInstanceOf(AlreadyOnboardedError);
  });
});
