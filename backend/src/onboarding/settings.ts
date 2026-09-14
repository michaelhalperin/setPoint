import type { PrismaClient } from '@prisma/client';
import { weekendBreakfastSuggestion, type WeekendBreakfastSuggestion } from '../dashboard/record.js';
import { OnboardingIncompleteError } from '../dashboard/home.js';
import { DEFAULT_WEEKEND_DAYS, type WeekendMealTimes } from '../engine/mealSchedule.js';
import { localDateISO, msSinceLocalMidnight, shiftDateISO } from '../engine/time.js';
import type { Goal } from '../engine/types.js';
import { normalizeToken } from '../solver/exclusions.js';
import { deriveTargets } from './recompute.js';
import { assertHealthyTarget, minHealthyWeightKg, remainingKg, resolveGoalPace } from './targets.js';

export type SettingsView = {
  goal: Goal;
  mode: string;
  timezone: string;
  dailyKcalTarget: number;
  dailyProteinTargetG: number | null;
  targetWeightKg: number | null;
  paceKgPerWeek: number;
  preferredDurationWeeks: number | null;
  startWeightKg: number | null;
  currentWeightKg: number | null;
  heightCm: number | null;
  /** Lowest DIET target accepted for this height (BMI 18.5); null without a height. */
  minHealthyWeightKg: number | null;
  mealTimes: { breakfastMin: number; lunchMin: number; dinnerMin: number };
  weekendMealTimes: WeekendMealTimes;
  weekendDays: number;
  weekendSuggestion: WeekendBreakfastSuggestion | null;
  quietHours: { startMin: number; endMin: number };
  checkInsPaused: boolean;
  restrictions: { label: string; token: string; source: string }[];
  pantryTokens: string[];
  dislikedFoods: string[];
  prepTimeMaxMin: number | null;
  enforcementEnabled: boolean;
  enforcementDisabledReason: string | null;
  healthWrite: {
    energy: boolean;
    protein: boolean;
    carbs: boolean;
    fat: boolean;
    bodyMass: boolean;
  };
  calendar: {
    enabled: boolean;
    leadMin: number;
    minBlockMin: number;
    workdaysOnly: boolean;
    includeAllDay: boolean;
  };
};

export type SettingsPatch = {
  goal?: Goal;
  mode?: 'BASIC' | 'SMART';
  targetWeightKg?: number | null;
  paceKgPerWeek?: number;
  preferredDurationWeeks?: number | null;
  dailyKcalTarget?: number;
  dailyProteinTargetG?: number | null;
  mealTimes?: { breakfastMin: number; lunchMin: number; dinnerMin: number };
  weekendMealTimes?: WeekendMealTimes;
  weekendDays?: number;
  quietHours?: { startMin: number; endMin: number };
  checkInsPaused?: boolean;
  timezone?: string;
  /** Full replace of the restriction set when present. */
  restrictions?: { label: string; source?: string }[];
  pantryTokens?: string[];
  dislikedFoods?: string[];
  prepTimeMaxMin?: number | null;
  healthWrite?: {
    energy: boolean;
    protein: boolean;
    carbs: boolean;
    fat: boolean;
    bodyMass: boolean;
  };
  calendar?: {
    enabled?: boolean;
    leadMin?: number;
    minBlockMin?: number;
    workdaysOnly?: boolean;
    includeAllDay?: boolean;
  };
};

export async function getSettings(
  deps: { prisma: PrismaClient; now?: Date },
  userId: string,
): Promise<SettingsView> {
  const user = await loadForView(deps.prisma, userId);
  if (!user?.onboarding) throw new OnboardingIncompleteError('onboarding not complete');
  const suggestion = await loadWeekendSuggestion(deps.prisma, user, deps.now ?? new Date());
  return toView(user, suggestion);
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
      goalChanged ||
      patch.targetWeightKg !== undefined ||
      patch.paceKgPerWeek !== undefined ||
      patch.preferredDurationWeeks !== undefined;

    if (weightGoalTouched) {
      if (nextGoal === 'MAINTAIN') {
        profileData.goal = 'MAINTAIN';
        profileData.targetWeightKg = null;
        profileData.paceKgPerWeek = 0;
        profileData.preferredDurationWeeks = null;
        profileData.goalStartedAt = null;
      } else {
        const latest = await tx.weightEntry.findFirst({
          where: { userId },
          orderBy: { measuredAt: 'desc' },
        });
        const currentWeight = latest?.weightKg ?? profile.weightKg ?? null;
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

        const remaining = remainingKg(nextGoal, currentWeight, target);
        const duration = durationForPatch(patch, profile, goalChanged);
        const resolved = resolveGoalPace({
          goal: nextGoal,
          weightKg: currentWeight,
          remainingKg: remaining,
          preferredDurationWeeks: duration,
          paceKgPerWeek: patch.paceKgPerWeek ?? profile.paceKgPerWeek,
        });

        profileData.goal = nextGoal;
        profileData.paceKgPerWeek = resolved.paceKgPerWeek;
        profileData.preferredDurationWeeks = resolved.preferredDurationWeeks;
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
              paceKgPerWeek: resolved.paceKgPerWeek,
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
    if (patch.weekendMealTimes) {
      profileData.weekendBreakfastMin = patch.weekendMealTimes.breakfastMin;
      profileData.weekendLunchMin = patch.weekendMealTimes.lunchMin;
      profileData.weekendDinnerMin = patch.weekendMealTimes.dinnerMin;
    }
    if (patch.weekendDays != null) {
      profileData.weekendDays = patch.weekendDays;
    }
    if (patch.quietHours) {
      profileData.quietHoursStartMin = patch.quietHours.startMin;
      profileData.quietHoursEndMin = patch.quietHours.endMin;
    }
    if (patch.mode) profileData.mode = patch.mode;
    if (patch.pantryTokens) profileData.pantryTokens = patch.pantryTokens.map((t) => t.trim()).filter(Boolean);
    if (patch.dislikedFoods) profileData.dislikedFoods = patch.dislikedFoods.map((t) => t.trim()).filter(Boolean);
    if (patch.prepTimeMaxMin !== undefined) profileData.prepTimeMaxMin = patch.prepTimeMaxMin;
    if (patch.healthWrite) {
      profileData.writeHealthEnergy = patch.healthWrite.energy;
      profileData.writeHealthProtein = patch.healthWrite.protein;
      profileData.writeHealthCarbs = patch.healthWrite.carbs;
      profileData.writeHealthFat = patch.healthWrite.fat;
      profileData.writeHealthBodyMass = patch.healthWrite.bodyMass;
    }
    if (patch.calendar) {
      if (patch.calendar.enabled != null) profileData.calendarEnabled = patch.calendar.enabled;
      if (patch.calendar.leadMin != null) profileData.calendarLeadMin = patch.calendar.leadMin;
      if (patch.calendar.minBlockMin != null) profileData.calendarMinBlockMin = patch.calendar.minBlockMin;
      if (patch.calendar.workdaysOnly != null) profileData.calendarWorkdaysOnly = patch.calendar.workdaysOnly;
      if (patch.calendar.includeAllDay != null) profileData.calendarIncludeAllDay = patch.calendar.includeAllDay;
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

async function loadWeekendSuggestion(
  prisma: PrismaClient,
  user: UserWithSettings,
  now: Date,
): Promise<WeekendBreakfastSuggestion | null> {
  const p = user.onboarding!;
  const today = localDateISO(now, user.timezone);
  const from = new Date(now.getTime() - 22 * 86_400_000);
  const meals = await prisma.meal.findMany({
    where: { userId: user.id, loggedAt: { gte: from } },
    select: { loggedAt: true },
  });
  const dates: string[] = [];
  for (let i = 21; i >= 0; i -= 1) dates.push(shiftDateISO(today, -i));
  return weekendBreakfastSuggestion({
    datesOldestFirst: dates,
    today,
    meals: meals.map((m) => ({
      date: localDateISO(m.loggedAt, user.timezone),
      minute: Math.floor(msSinceLocalMidnight(m.loggedAt, user.timezone) / 60_000),
    })),
    weekdayBreakfastMin: p.breakfastMin,
    weekendDays: p.weekendDays ?? DEFAULT_WEEKEND_DAYS,
  });
}

function toView(user: UserWithSettings, weekendSuggestion: WeekendBreakfastSuggestion | null): SettingsView {
  const p = user.onboarding!;
  return {
    goal: p.goal as Goal,
    mode: p.mode,
    timezone: user.timezone,
    dailyKcalTarget: p.dailyKcalTarget,
    dailyProteinTargetG: p.dailyProteinTargetG,
    targetWeightKg: p.targetWeightKg,
    paceKgPerWeek: p.paceKgPerWeek,
    preferredDurationWeeks: p.preferredDurationWeeks ?? null,
    startWeightKg: p.startWeightKg,
    currentWeightKg: user.weightEntries[0]?.weightKg ?? p.weightKg ?? null,
    heightCm: p.heightCm,
    minHealthyWeightKg: p.heightCm != null ? minHealthyWeightKg(p.heightCm) : null,
    mealTimes: { breakfastMin: p.breakfastMin, lunchMin: p.lunchMin, dinnerMin: p.dinnerMin },
    weekendMealTimes: {
      breakfastMin: p.weekendBreakfastMin ?? null,
      lunchMin: p.weekendLunchMin ?? null,
      dinnerMin: p.weekendDinnerMin ?? null,
    },
    weekendDays: p.weekendDays ?? DEFAULT_WEEKEND_DAYS,
    weekendSuggestion,
    quietHours: { startMin: p.quietHoursStartMin, endMin: p.quietHoursEndMin },
    checkInsPaused: user.escalationState?.checkInsPaused ?? false,
    restrictions: user.restrictions.map((r) => ({ label: r.label, token: r.token, source: r.source })),
    pantryTokens: p.pantryTokens ?? [],
    dislikedFoods: p.dislikedFoods ?? [],
    prepTimeMaxMin: p.prepTimeMaxMin ?? null,
    enforcementEnabled: user.safetyScreening?.enforcementEnabled ?? false,
    enforcementDisabledReason: user.safetyScreening?.enforcementDisabledReason ?? null,
    healthWrite: {
      energy: p.writeHealthEnergy ?? true,
      protein: p.writeHealthProtein ?? true,
      carbs: p.writeHealthCarbs ?? true,
      fat: p.writeHealthFat ?? true,
      bodyMass: p.writeHealthBodyMass ?? false,
    },
    calendar: {
      enabled: p.calendarEnabled ?? false,
      leadMin: p.calendarLeadMin ?? 45,
      minBlockMin: p.calendarMinBlockMin ?? 60,
      workdaysOnly: p.calendarWorkdaysOnly ?? true,
      includeAllDay: p.calendarIncludeAllDay ?? false,
    },
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

/**
 * Duration wins when the client sends it. A goal switch without a timeframe
 * drops the old one (pace/pills start the new plan). A target-only tweak keeps
 * the stored weeks so the user isn't bounced back to an auto ETA.
 */
function durationForPatch(
  patch: SettingsPatch,
  profile: { preferredDurationWeeks?: number | null },
  goalChanged: boolean,
): number | null {
  if (patch.preferredDurationWeeks !== undefined) return patch.preferredDurationWeeks;
  if (goalChanged) return null;
  if (patch.paceKgPerWeek !== undefined && patch.targetWeightKg === undefined) return null;
  return profile.preferredDurationWeeks ?? null;
}
