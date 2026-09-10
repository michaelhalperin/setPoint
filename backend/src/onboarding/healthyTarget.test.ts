import type { PrismaClient } from '@prisma/client';
import { describe, expect, it, vi } from 'vitest';
import { runOnboarding, type OnboardingInput } from './onboard.js';
import { updateSettings } from './settings.js';
import { UnhealthyTargetError, assertHealthyTarget, minHealthyWeightKg } from './targets.js';

describe('minHealthyWeightKg', () => {
  it('is BMI 18.5 at the height, rounded up to 0.1 kg', () => {
    expect(minHealthyWeightKg(175)).toBe(56.7); // 18.5 × 1.75² = 56.66
    expect(minHealthyWeightKg(160)).toBe(47.4); // 18.5 × 1.60² = 47.36
  });
});

describe('assertHealthyTarget', () => {
  it('rejects a diet target below the floor and reports the floor', () => {
    expect(() => assertHealthyTarget('DIET', 52, 175)).toThrowError(UnhealthyTargetError);
    try {
      assertHealthyTarget('DIET', 52, 175);
    } catch (err) {
      expect((err as UnhealthyTargetError).minWeightKg).toBe(56.7);
    }
  });

  it('accepts a diet target at or above the floor', () => {
    expect(() => assertHealthyTarget('DIET', 56.7, 175)).not.toThrow();
    expect(() => assertHealthyTarget('DIET', 70, 175)).not.toThrow();
  });

  it('only checks diets with a known target and height', () => {
    expect(() => assertHealthyTarget('BULK', 40, 175)).not.toThrow();
    expect(() => assertHealthyTarget('MAINTAIN', 40, 175)).not.toThrow();
    expect(() => assertHealthyTarget('DIET', null, 175)).not.toThrow();
    expect(() => assertHealthyTarget('DIET', 40, null)).not.toThrow();
  });
});

describe('the floor at the entry points', () => {
  const onboardingInput = (over: Partial<OnboardingInput> = {}): OnboardingInput => ({
    goal: 'DIET',
    mode: 'BASIC',
    sex: 'FEMALE',
    birthDate: '1996-01-01',
    heightCm: 165,
    weightKg: 58,
    activityLevel: 'LIGHT',
    targetWeightKg: 45,
    paceKgPerWeek: 0.25,
    safety: {
      medicalSupervisionRequired: false,
      scoff: { makeSelfSick: false, lostControl: false, lostOneStone: false, believesFat: false, foodDominates: false },
    },
    ...over,
  });

  it('onboarding refuses an underweight diet target before writing anything', async () => {
    const transaction = vi.fn();
    const prisma = {
      onboardingProfile: { findUnique: async () => null },
      $transaction: transaction,
    } as unknown as PrismaClient;

    await expect(runOnboarding({ prisma }, 'u1', onboardingInput())).rejects.toBeInstanceOf(UnhealthyTargetError);
    expect(transaction).not.toHaveBeenCalled();
  });

  it('settings refuse to move a diet target below the floor', async () => {
    const update = vi.fn();
    const profile = {
      goal: 'DIET',
      heightCm: 165,
      weightKg: 58,
      targetWeightKg: 52,
      paceKgPerWeek: 0.25,
      startWeightKg: 60,
      goalStartedAt: new Date('2026-08-01'),
      sex: 'FEMALE',
      birthDate: new Date('1996-01-01'),
      activityLevel: 'LIGHT',
    };
    const prisma = {
      onboardingProfile: { findUnique: async () => profile, update },
      weightEntry: { findFirst: async () => null },
      $transaction: async (fn: (tx: unknown) => Promise<unknown>) => fn(prisma),
    } as unknown as PrismaClient;

    await expect(updateSettings({ prisma }, 'u1', { targetWeightKg: 45 })).rejects.toBeInstanceOf(
      UnhealthyTargetError,
    );
    expect(update).not.toHaveBeenCalled();
  });
});
