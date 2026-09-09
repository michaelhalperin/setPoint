import type { PrismaClient } from '@prisma/client';
import type { Goal } from '../engine/types.js';
import { OnboardingIncompleteError } from '../dashboard/home.js';
import { deriveTargets } from '../onboarding/recompute.js';
import { computeWeightProgress, type WeightProgress } from './progress.js';

export class InvalidWeightError extends Error {}

export type LogWeightInput = {
  weightKg: number;
  measuredAt?: Date;
  source?: 'manual' | 'healthkit';
};

export type LogWeightResult = {
  entry: { id: string; weightKg: number; measuredAt: string; source: string };
  progress: WeightProgress | null;
  /** True when this measurement reached the goal and flipped it to MAINTAIN. */
  goalReached: boolean;
  goal: Goal;
  dailyKcalTarget: number;
  dailyProteinTargetG: number | null;
};

const MIN_KG = 25;
const MAX_KG = 400;

export async function logWeight(
  deps: { prisma: PrismaClient; now?: Date },
  userId: string,
  input: LogWeightInput,
): Promise<LogWeightResult> {
  const now = deps.now ?? new Date();
  const { prisma } = deps;

  if (!Number.isFinite(input.weightKg) || input.weightKg < MIN_KG || input.weightKg > MAX_KG) {
    throw new InvalidWeightError(`weight must be between ${MIN_KG} and ${MAX_KG} kg`);
  }
  const measuredAt = input.measuredAt ?? now;
  if (measuredAt.getTime() > now.getTime() + 60_000) {
    throw new InvalidWeightError('measuredAt cannot be in the future');
  }
  const source = input.source ?? 'manual';
  const weightKg = round1(input.weightKg);

  const profile = await prisma.onboardingProfile.findUnique({ where: { userId } });
  if (!profile) throw new OnboardingIncompleteError('onboarding not complete');

  const entry = await prisma.weightEntry.upsert({
    where: { userId_measuredAt: { userId, measuredAt } },
    create: { userId, weightKg, measuredAt, source },
    update: { weightKg, source },
  });

  const goal = profile.goal as Goal;
  let progress = computeWeightProgress({
    goal,
    startWeightKg: profile.startWeightKg,
    targetWeightKg: profile.targetWeightKg,
    currentWeightKg: weightKg,
    paceKgPerWeek: profile.paceKgPerWeek,
    goalStartedAt: profile.goalStartedAt,
    now,
  });

  let finalGoal = goal;
  let dailyKcalTarget = profile.dailyKcalTarget;
  let dailyProteinTargetG = profile.dailyProteinTargetG;
  let goalReached = false;

  if (progress?.reached && (goal === 'BULK' || goal === 'DIET')) {
    goalReached = true;
    finalGoal = 'MAINTAIN';
    const derived = deriveTargets(
      {
        sex: profile.sex,
        birthDate: profile.birthDate,
        heightCm: profile.heightCm,
        weightKg,
        activityLevel: profile.activityLevel,
        goal: 'MAINTAIN',
        paceKgPerWeek: 0,
      },
      now,
    );
    dailyKcalTarget = derived.dailyKcalTarget ?? profile.dailyKcalTarget;
    dailyProteinTargetG = derived.dailyProteinTargetG ?? profile.dailyProteinTargetG;

    await prisma.onboardingProfile.update({
      where: { userId },
      data: { goal: 'MAINTAIN', paceKgPerWeek: 0, dailyKcalTarget, dailyProteinTargetG },
    });
    // Progress is done — recompute against MAINTAIN so the response is consistent.
    progress = null;
  }

  return {
    entry: {
      id: entry.id,
      weightKg: entry.weightKg,
      measuredAt: entry.measuredAt.toISOString(),
      source: entry.source,
    },
    progress,
    goalReached,
    goal: finalGoal,
    dailyKcalTarget,
    dailyProteinTargetG,
  };
}

const round1 = (n: number): number => Math.round(n * 10) / 10;
