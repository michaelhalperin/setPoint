import type { PrismaClient } from '@prisma/client';
import type { Goal } from '../engine/types.js';
import { normalizeToken } from '../solver/exclusions.js';
import { OnboardingIncompleteError } from '../dashboard/home.js';
import { deriveTargets } from './recompute.js';
import { assertHealthyTarget, clampPaceKgPerWeek, minHealthyWeightKg } from './targets.js';

export type SettingsView = {
  goal: Goal;
  mode: string;
  timezone: string;
  dailyKcalTarget: number;
  dailyProteinTargetG: number | null;
  targetWeightKg: number | null;
  paceKgPerWeek: number;
  startWeightKg: number | null;
  currentWeightKg: number | null;
  heightCm: number | null;
  /** Lowest DIET target accepted for this height (BMI 18.5); null without a height. */
  minHealthyWeightKg: number | null;
  mealTimes: { breakfastMin: number; lunchMin: number; dinnerMin: number };
  quietHours: { startMin: number; endMin: number };
  checkInsPaused: boolean;
  restrictions: { label: string; token: string; source: string }[];
  enforcementEnabled: boolean;
  enforcementDisabledReason: string | null;
};

export type SettingsPatch = {
  goal?: Goal;
  targetWeightKg?: number | null;
  paceKgPerWeek?: number;
  dailyKcalTarget?: number;
  dailyProteinTargetG?: number | null;
  mealTimes?: { breakfastMin: number; lunchMin: number; dinnerMin: number };
  quietHours?: { startMin: number; endMin: number };
  checkInsPaused?: boolean;
  timezone?: string;
  /** Full replace of the restriction set when present. */
  restrictions?: { label: string; source?: string }[];
};

export async function getSettings(
  deps: { prisma: PrismaClient },
  userId: string,
): Promise<SettingsView> {
  const user = await loadForView(deps.prisma, userId);
  if (!user?.onboarding) throw new OnboardingIncompleteError('onboarding not complete');
  return toView(user);
}

export async function updateSettings(
  deps: { prisma: PrismaClient; now?: Date },
  userId: string,
  patch: SettingsPatch,
): Promise<SettingsView> {
  const { prisma } = deps;
  const now = deps.now ?? new Date();

  await prisma.$transaction(async (tx) => {
    const profile = await tx.onboardingProfile.findUnique({ where: { userId } });
    if (!profile) throw new OnboardingIncompleteError('onboarding not complete');

    const profileData: Record<string, unknown> = {};

    // --- Weight goal (M16) ------------------------------------------------
    const goalChanged = patch.goal != null && patch.goal !== profile.goal;
    const nextGoal = (patch.goal ?? profile.goal) as Goal;
    const weightGoalTouched =
      goalChanged || patch.targetWeightKg !== undefined || patch.paceKgPerWeek !== undefined;

    if (weightGoalTouched) {
      if (nextGoal === 'MAINTAIN') {
        profileData.goal = 'MAINTAIN';
        profileData.targetWeightKg = null;
        profileData.paceKgPerWeek = 0;
        profileData.goalStartedAt = null;
      } else {
        const latest = await tx.weightEntry.findFirst({
          where: { userId },
          orderBy: { measuredAt: 'desc' },
        });
        const currentWeight = latest?.weightKg ?? profile.weightKg ?? null;
        const pace = clampPaceKgPerWeek(
          nextGoal,
          currentWeight,
          patch.paceKgPerWeek ?? profile.paceKgPerWeek,
        );
        const target =
          patch.targetWeightKg !== undefined
            ? patch.targetWeightKg
            : (profile.targetWeightKg ?? null);

        // Safety floor: a diet target never goes below a healthy weight for the
        // height. Checked when the goal or target changes, so an unrelated edit
        // never gets stuck on a target saved before the floor existed.
        if (goalChanged || target !== profile.targetWeightKg) {
          assertHealthyTarget(nextGoal, target, profile.heightCm);
        }

        profileData.goal = nextGoal;
        profileData.paceKgPerWeek = pace;
        profileData.targetWeightKg = target;

        // Switching goal (or setting one up for the first time) re-anchors
        // progress to the current weight; a pace/target tweak keeps the anchor.
        if (goalChanged || profile.startWeightKg == null || profile.goalStartedAt == null) {
          profileData.startWeightKg = currentWeight;
          profileData.goalStartedAt = now;
        }

        // Recompute the daily targets from the new goal/pace unless the patch
        // sets them explicitly below.
        if (patch.dailyKcalTarget == null) {
          const derived = deriveTargets(
            {
              sex: profile.sex,
              birthDate: profile.birthDate,
              heightCm: profile.heightCm,
              weightKg: currentWeight,
              activityLevel: profile.activityLevel,
              goal: nextGoal,
              paceKgPerWeek: pace,
            },
            now,
          );
          if (derived.dailyKcalTarget != null) profileData.dailyKcalTarget = derived.dailyKcalTarget;
          if (patch.dailyProteinTargetG === undefined && derived.dailyProteinTargetG != null) {
            profileData.dailyProteinTargetG = derived.dailyProteinTargetG;
          }
        }
      }
    }

    // --- Explicit overrides & other fields ------------------------------
    if (patch.dailyKcalTarget != null) profileData.dailyKcalTarget = patch.dailyKcalTarget;
    if (patch.dailyProteinTargetG !== undefined) profileData.dailyProteinTargetG = patch.dailyProteinTargetG;
    if (patch.mealTimes) {
      profileData.breakfastMin = patch.mealTimes.breakfastMin;
      profileData.lunchMin = patch.mealTimes.lunchMin;
      profileData.dinnerMin = patch.mealTimes.dinnerMin;
    }
    if (patch.quietHours) {
      profileData.quietHoursStartMin = patch.quietHours.startMin;
      profileData.quietHoursEndMin = patch.quietHours.endMin;
    }
    if (Object.keys(profileData).length > 0) {
      await tx.onboardingProfile.update({ where: { userId }, data: profileData });
    }

    if (patch.timezone) {
      await tx.user.update({ where: { id: userId }, data: { timezone: patch.timezone } });
    }

    if (patch.checkInsPaused !== undefined) {
      await tx.escalationState.upsert({
        where: { userId },
        create: { userId, checkInsPaused: patch.checkInsPaused },
        update: { checkInsPaused: patch.checkInsPaused },
      });
    }

    if (patch.restrictions) {
      await tx.dietaryRestriction.deleteMany({ where: { userId } });
      const rows = dedupe(patch.restrictions).map((r) => ({ userId, ...r }));
      if (rows.length > 0) await tx.dietaryRestriction.createMany({ data: rows });
    }
  });

  return getSettings(deps, userId);
}

type UserWithSettings = NonNullable<Awaited<ReturnType<typeof loadForView>>>;
function loadForView(prisma: PrismaClient, userId: string) {
  return prisma.user.findUnique({
    where: { id: userId },
    include: {
      onboarding: true,
      safetyScreening: true,
      escalationState: true,
      restrictions: true,
      weightEntries: { orderBy: { measuredAt: 'desc' }, take: 1 },
    },
  });
}

function toView(user: UserWithSettings): SettingsView {
  const p = user.onboarding!;
  return {
    goal: p.goal as Goal,
    mode: p.mode,
    timezone: user.timezone,
    dailyKcalTarget: p.dailyKcalTarget,
    dailyProteinTargetG: p.dailyProteinTargetG,
    targetWeightKg: p.targetWeightKg,
    paceKgPerWeek: p.paceKgPerWeek,
    startWeightKg: p.startWeightKg,
    currentWeightKg: user.weightEntries[0]?.weightKg ?? p.weightKg ?? null,
    heightCm: p.heightCm,
    minHealthyWeightKg: p.heightCm != null ? minHealthyWeightKg(p.heightCm) : null,
    mealTimes: { breakfastMin: p.breakfastMin, lunchMin: p.lunchMin, dinnerMin: p.dinnerMin },
    quietHours: { startMin: p.quietHoursStartMin, endMin: p.quietHoursEndMin },
    checkInsPaused: user.escalationState?.checkInsPaused ?? false,
    restrictions: user.restrictions.map((r) => ({ label: r.label, token: r.token, source: r.source })),
    enforcementEnabled: user.safetyScreening?.enforcementEnabled ?? false,
    enforcementDisabledReason: user.safetyScreening?.enforcementDisabledReason ?? null,
  };
}

const SOURCES = new Set(['ALLERGY', 'INTOLERANCE', 'PREFERENCE', 'RELIGIOUS', 'MEDICAL']);

function dedupe(
  raw: { label: string; source?: string }[],
): { label: string; token: string; source: 'ALLERGY' | 'INTOLERANCE' | 'PREFERENCE' | 'RELIGIOUS' | 'MEDICAL' }[] {
  const seen = new Map<string, { label: string; token: string; source: never }>();
  for (const r of raw) {
    const token = normalizeToken(r.label);
    if (!token || seen.has(token)) continue;
    const source = (r.source ?? 'ALLERGY').toUpperCase();
    seen.set(token, {
      label: r.label.trim(),
      token,
      source: (SOURCES.has(source) ? source : 'ALLERGY') as never,
    });
  }
  return [...seen.values()];
}
