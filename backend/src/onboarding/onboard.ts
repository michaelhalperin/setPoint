import type { PrismaClient } from '@prisma/client';
import type { Goal } from '../engine/types.js';
import { normalizeToken } from '../solver/exclusions.js';
import {
  ageFromBirthDate,
  computeCalorieTarget,
  computeProteinTarget,
  type ActivityLevel,
  type Sex,
} from './targets.js';
import { deriveEnforcement, scoffFlagged, scoffScore, type ScoffAnswers } from './scoff.js';

export class AlreadyOnboardedError extends Error {}
export class MissingTargetError extends Error {}

export type OnboardingRestriction = { label: string; source?: string };

export type OnboardingInput = {
  goal: Goal;
  mode: 'BASIC' | 'SMART';
  timezone?: string;

  sex?: Sex;
  birthDate?: string;
  heightCm?: number;
  weightKg?: number;
  activityLevel?: ActivityLevel;

  /** Explicit override; otherwise computed from stats. Required when stats are absent. */
  dailyKcalTarget?: number;
  dailyProteinTargetG?: number;

  mealTimes?: { breakfastMin: number; lunchMin: number; dinnerMin: number };
  quietHours?: { startMin: number; endMin: number };

  safety: {
    medicalSupervisionRequired: boolean;
    scoff: ScoffAnswers;
    restrictions?: OnboardingRestriction[];
    restrictionsFreeText?: string;
  };
};

export type OnboardingResult = {
  dailyKcalTarget: number;
  dailyProteinTargetG: number | null;
  enforcementEnabled: boolean;
  enforcementDisabledReason: string | null;
};

const RESTRICTION_SOURCES = new Set(['ALLERGY', 'INTOLERANCE', 'PREFERENCE', 'RELIGIOUS', 'MEDICAL']);

export async function runOnboarding(
  deps: { prisma: PrismaClient; now?: Date },
  userId: string,
  input: OnboardingInput,
): Promise<OnboardingResult> {
  const now = deps.now ?? new Date();
  const { prisma } = deps;

  const existing = await prisma.onboardingProfile.findUnique({ where: { userId } });
  if (existing?.completedAt) throw new AlreadyOnboardedError('already onboarded');

  // Targets: compute from stats when present, else require an explicit value.
  const hasStats =
    input.weightKg != null && input.heightCm != null && input.birthDate != null && input.activityLevel != null;

  let dailyKcalTarget: number;
  let dailyProteinTargetG: number | null;

  if (hasStats) {
    const stats = {
      sex: input.sex ?? 'UNSPECIFIED',
      weightKg: input.weightKg!,
      heightCm: input.heightCm!,
      ageYears: ageFromBirthDate(new Date(input.birthDate!), now),
      activityLevel: input.activityLevel!,
    };
    dailyKcalTarget = input.dailyKcalTarget ?? computeCalorieTarget(stats, input.goal);
    dailyProteinTargetG = input.dailyProteinTargetG ?? computeProteinTarget(input.weightKg!, input.goal);
  } else if (input.dailyKcalTarget != null) {
    dailyKcalTarget = input.dailyKcalTarget;
    dailyProteinTargetG = input.dailyProteinTargetG ?? null;
  } else {
    throw new MissingTargetError('provide body stats or an explicit dailyKcalTarget');
  }

  const score = scoffScore(input.safety.scoff);
  const flagged = scoffFlagged(input.safety.scoff);
  const enforcement = deriveEnforcement(input.safety.medicalSupervisionRequired, flagged);

  const mealTimes = input.mealTimes ?? { breakfastMin: 480, lunchMin: 780, dinnerMin: 1140 };
  const quietHours = input.quietHours ?? { startMin: 1380, endMin: 420 };

  const restrictions = dedupeRestrictions(input.safety.restrictions ?? []);

  await prisma.$transaction(async (tx) => {
    if (input.timezone) {
      await tx.user.update({ where: { id: userId }, data: { timezone: input.timezone } });
    }

    await tx.onboardingProfile.upsert({
      where: { userId },
      create: {
        userId,
        goal: input.goal,
        mode: input.mode,
        sex: input.sex ?? 'UNSPECIFIED',
        birthDate: input.birthDate ? new Date(input.birthDate) : null,
        heightCm: input.heightCm ?? null,
        weightKg: input.weightKg ?? null,
        activityLevel: input.activityLevel ?? 'MODERATE',
        dailyKcalTarget,
        dailyProteinTargetG,
        breakfastMin: mealTimes.breakfastMin,
        lunchMin: mealTimes.lunchMin,
        dinnerMin: mealTimes.dinnerMin,
        quietHoursStartMin: quietHours.startMin,
        quietHoursEndMin: quietHours.endMin,
        completedAt: now,
      },
      update: {
        goal: input.goal,
        mode: input.mode,
        dailyKcalTarget,
        dailyProteinTargetG,
        breakfastMin: mealTimes.breakfastMin,
        lunchMin: mealTimes.lunchMin,
        dinnerMin: mealTimes.dinnerMin,
        quietHoursStartMin: quietHours.startMin,
        quietHoursEndMin: quietHours.endMin,
        completedAt: now,
      },
    });

    await tx.safetyScreening.upsert({
      where: { userId },
      create: {
        userId,
        medicalSupervisionRequired: input.safety.medicalSupervisionRequired,
        scoffMakeSelfSick: input.safety.scoff.makeSelfSick,
        scoffLostControl: input.safety.scoff.lostControl,
        scoffLostOneStone: input.safety.scoff.lostOneStone,
        scoffBelievesFat: input.safety.scoff.believesFat,
        scoffFoodDominates: input.safety.scoff.foodDominates,
        scoffScore: score,
        scoffFlagged: flagged,
        restrictionsFreeText: input.safety.restrictionsFreeText ?? null,
        enforcementEnabled: enforcement.enforcementEnabled,
        enforcementDisabledReason: enforcement.enforcementDisabledReason,
      },
      update: {
        medicalSupervisionRequired: input.safety.medicalSupervisionRequired,
        scoffScore: score,
        scoffFlagged: flagged,
        restrictionsFreeText: input.safety.restrictionsFreeText ?? null,
        enforcementEnabled: enforcement.enforcementEnabled,
        enforcementDisabledReason: enforcement.enforcementDisabledReason,
      },
    });

    await tx.dietaryRestriction.deleteMany({ where: { userId } });
    if (restrictions.length > 0) {
      await tx.dietaryRestriction.createMany({
        data: restrictions.map((r) => ({ userId, label: r.label, token: r.token, source: r.source })),
      });
    }

    await tx.escalationState.upsert({
      where: { userId },
      create: { userId },
      update: {},
    });
  });

  return {
    dailyKcalTarget,
    dailyProteinTargetG,
    enforcementEnabled: enforcement.enforcementEnabled,
    enforcementDisabledReason: enforcement.enforcementDisabledReason,
  };
}

function dedupeRestrictions(
  raw: OnboardingRestriction[],
): { label: string; token: string; source: 'ALLERGY' | 'INTOLERANCE' | 'PREFERENCE' | 'RELIGIOUS' | 'MEDICAL' }[] {
  const seen = new Map<string, { label: string; token: string; source: never }>();
  for (const r of raw) {
    const token = normalizeToken(r.label);
    if (!token || seen.has(token)) continue;
    const source = (r.source ?? 'ALLERGY').toUpperCase();
    seen.set(token, {
      label: r.label.trim(),
      token,
      source: (RESTRICTION_SOURCES.has(source) ? source : 'ALLERGY') as never,
    });
  }
  return [...seen.values()];
}
