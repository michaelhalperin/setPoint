import type { PrismaClient } from '@prisma/client';
import {
  checkInSlotAt,
  hoursBetween,
  isWithinQuietHours,
  msSinceLocalMidnight,
  startOfLocalDay,
  TIER,
  upcomingCheckIn,
  type Goal,
  type ScheduledCheckIn,
  type SlotName,
} from '../engine/index.js';
import type { ManagerVoice } from '../managerVoice/types.js';
import { toMealSummaries, type MealSummary } from '../meals/summary.js';
import type { PhotoStore } from '../photos/store.js';
import { homeFraming, type FramingState } from './classify.js';
import { buildDay, type DayView } from './day.js';
import { mealWindow } from '../managerVoice/fallback.js';

export type HomeDeps = {
  prisma: PrismaClient;
  voice: ManagerVoice;
  /** Signs meal-photo URLs. Null/absent: stored photos are omitted. */
  photos?: PhotoStore | null;
  now?: Date;
};

export type HomeView = {
  goal: Goal;
  mode: string;
  enforcementEnabled: boolean;
  ledger: {
    consumedKcal: number;
    targetKcal: number;
    remainingKcal: number;
    consumedProteinG: number;
    targetProteinG: number | null;
    remainingProteinG: number | null;
    mealsToday: number;
    lastMealAt: string | null;
  };
  framing: {
    state: FramingState;
    accent: boolean;
    primaryCta: 'log_meal' | null;
    heroKcal: number;
  };
  managerNote: string;
  meals: MealSummary[];
  mealTimes: { breakfastMin: number; lunchMin: number; dinnerMin: number };
  quietHours: { startMin: number; endMin: number };
  /** Today's meal-time slots, where now sits, and pace (pace is null in quiet mode). */
  day: DayView;
  /**
   * The check-in the user will get if nothing is logged ("Next check-in 13:45").
   * Null in quiet mode, while paused, while one is already open, or once the day is covered.
   */
  nextCheckIn: ScheduledCheckIn | null;
  activeCheckIn: null | {
    id: string;
    tier: number;
    /** The meal it's about; null for a tier-3 conversation. */
    slot: SlotName | null;
    status: string;
    message: string | null;
    deferUntil: string | null;
    prescription: null | {
      id: string;
      totalKcal: number;
      totalProteinG: number;
      items: { name: string; quantity: number; kcal: number; proteinG: number }[];
    };
  };
};

const round1 = (n: number): number => Math.round(n * 10) / 10;

export class OnboardingIncompleteError extends Error {}

export async function buildHome(deps: HomeDeps, userId: string): Promise<HomeView> {
  const now = deps.now ?? new Date();
  const { prisma } = deps;

  const user = await prisma.user.findUnique({
    where: { id: userId },
    include: { onboarding: true, safetyScreening: true, escalationState: true },
  });
  if (!user?.onboarding) throw new OnboardingIncompleteError('onboarding not complete');

  const profile = user.onboarding;
  const dayStart = startOfLocalDay(now, user.timezone);

  const [todayMeals, lastMeal, activeCheckIn, todayCheckIns] = await Promise.all([
    prisma.meal.findMany({
      where: { userId, loggedAt: { gte: dayStart } },
      orderBy: { loggedAt: 'asc' },
      select: {
        id: true,
        loggedAt: true,
        kcal: true,
        proteinG: true,
        carbsG: true,
        fatG: true,
        source: true,
        rawInput: true,
        photoUrl: true,
        photoKey: true,
        notes: true,
        items: true,
        parseConfidence: true,
      },
    }),
    prisma.meal.findFirst({ where: { userId }, orderBy: { loggedAt: 'desc' }, select: { loggedAt: true } }),
    prisma.checkIn.findFirst({
      where: { userId, status: { in: ['PENDING', 'DEFERRED'] } },
      orderBy: { createdAt: 'desc' },
      include: { prescription: { include: { items: true } } },
    }),
    prisma.checkIn.findMany({
      where: { userId, createdAt: { gte: dayStart } },
      select: { createdAt: true, tier: true },
    }),
  ]);

  const consumedKcal = todayMeals.reduce((acc, m) => acc + m.kcal, 0);
  const consumedProteinG = round1(todayMeals.reduce((acc, m) => acc + m.proteinG, 0));
  const targetKcal = profile.dailyKcalTarget;
  const targetProteinG = profile.dailyProteinTargetG;
  const goal = profile.goal as Goal;

  const framing = homeFraming(goal, consumedKcal, targetKcal);
  const remainingKcal = Math.round(targetKcal - consumedKcal);
  const remainingProteinG = targetProteinG === null ? null : round1(targetProteinG - consumedProteinG);
  const hoursSinceMeal = lastMeal ? hoursBetween(lastMeal.loggedAt, now) : null;
  const localMinute = (date: Date): number => Math.floor(msSinceLocalMidnight(date, user.timezone) / 60_000);
  const mins = localMinute(now);
  const enforcementEnabled = user.safetyScreening?.enforcementEnabled ?? false;

  const day = buildDay({
    nowMin: mins,
    mealTimes: { breakfastMin: profile.breakfastMin, lunchMin: profile.lunchMin, dinnerMin: profile.dinnerMin },
    meals: todayMeals.map((m) => ({
      id: m.id,
      minuteOfDay: localMinute(m.loggedAt),
      kcal: m.kcal,
    })),
    targetKcal,
    consumedKcal,
    framingState: framing.state,
    enforcementEnabled,
  });

  const escalation = user.escalationState;
  const checksRunning =
    enforcementEnabled &&
    !escalation?.checkInsPaused &&
    !(escalation?.backedOffUntil && escalation.backedOffUntil > now) &&
    activeCheckIn === null;
  const scheduled = checksRunning
    ? upcomingCheckIn({
        nowMin: mins,
        times: profile,
        mealMinutesToday: todayMeals.map((m) => localMinute(m.loggedAt)),
        checkedSlotsToday: todayCheckIns
          .filter((c) => c.tier < TIER.CONVERSATION)
          .map((c) => checkInSlotAt(localMinute(c.createdAt), profile))
          .filter((slot): slot is SlotName => slot !== null),
        consumedKcal,
        targetKcal,
      })
    : null;
  const nextCheckIn =
    scheduled && !isWithinQuietHours(scheduled.dueMin, profile.quietHoursStartMin, profile.quietHoursEndMin)
      ? scheduled
      : null;

  const managerNote = await deps.voice.homeNote({
    goal,
    state: framing.state,
    consumedKcal,
    targetKcal,
    remainingKcal,
    remainingProteinG,
    mealsToday: todayMeals.length,
    nextMeal:
      day.pace?.next?.slot ?? mealWindow(mins, { lunchMin: profile.lunchMin, dinnerMin: profile.dinnerMin }),
    hoursSinceMeal,
    hasActiveCheckIn: activeCheckIn !== null,
    enforcementEnabled,
    paceStatus: day.pace?.status ?? null,
  });

  return {
    goal,
    mode: profile.mode,
    enforcementEnabled,
    ledger: {
      consumedKcal,
      targetKcal,
      remainingKcal,
      consumedProteinG,
      targetProteinG,
      remainingProteinG,
      mealsToday: todayMeals.length,
      lastMealAt: lastMeal?.loggedAt.toISOString() ?? null,
    },
    framing: {
      state: framing.state,
      accent: framing.accent,
      primaryCta: framing.primaryCta,
      heroKcal: framing.heroKcal,
    },
    managerNote,
    meals: await toMealSummaries(todayMeals, deps.photos ?? null, now),
    mealTimes: {
      breakfastMin: profile.breakfastMin,
      lunchMin: profile.lunchMin,
      dinnerMin: profile.dinnerMin,
    },
    quietHours: { startMin: profile.quietHoursStartMin, endMin: profile.quietHoursEndMin },
    day,
    nextCheckIn,
    activeCheckIn: activeCheckIn
      ? {
          id: activeCheckIn.id,
          tier: activeCheckIn.tier,
          slot:
            activeCheckIn.tier < TIER.CONVERSATION
              ? checkInSlotAt(localMinute(activeCheckIn.createdAt), profile)
              : null,
          status: activeCheckIn.status,
          message: activeCheckIn.message,
          deferUntil: activeCheckIn.deferUntil?.toISOString() ?? null,
          prescription: activeCheckIn.prescription
            ? {
                id: activeCheckIn.prescription.id,
                totalKcal: activeCheckIn.prescription.totalKcal,
                totalProteinG: activeCheckIn.prescription.totalProteinG,
                items: activeCheckIn.prescription.items.map((i) => ({
                  name: i.name,
                  quantity: i.quantity,
                  kcal: i.kcal,
                  proteinG: i.proteinG,
                })),
              }
            : null,
        }
      : null,
  };
}
