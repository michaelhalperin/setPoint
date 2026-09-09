import type { PrismaClient } from '@prisma/client';
import type { Goal } from '../engine/types.js';
import { normalizeToken } from '../solver/exclusions.js';
import { OnboardingIncompleteError } from '../dashboard/home.js';

export type SettingsView = {
  goal: Goal;
  mode: string;
  timezone: string;
  dailyKcalTarget: number;
  dailyProteinTargetG: number | null;
  mealTimes: { breakfastMin: number; lunchMin: number; dinnerMin: number };
  quietHours: { startMin: number; endMin: number };
  checkInsPaused: boolean;
  restrictions: { label: string; token: string; source: string }[];
  enforcementEnabled: boolean;
  enforcementDisabledReason: string | null;
};

export type SettingsPatch = {
  goal?: Goal;
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
  deps: { prisma: PrismaClient },
  userId: string,
  patch: SettingsPatch,
): Promise<SettingsView> {
  const { prisma } = deps;

  await prisma.$transaction(async (tx) => {
    const profileData: Record<string, unknown> = {};
    if (patch.goal) profileData.goal = patch.goal;
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
    include: { onboarding: true, safetyScreening: true, escalationState: true, restrictions: true },
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
