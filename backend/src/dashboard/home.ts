import { AccountNotFoundError } from '../account/deleteAccount.js';
import type { PrismaClient } from '@prisma/client';
import {
  applyCalendarShift,
  checkInSlotAt,
  hoursBetween,
  isWithinQuietHours,
  localWeekday,
  mealTimesOn,
  msSinceLocalMidnight,
  prefsFromProfile,
  qualifyingBusyBlocks,
  slotNameOf,
  startOfLocalDay,
  TIER,
  toMinuteBlocks,
  upcomingCheckIn,
  movedSlotsToday,
  withOverdue,
  appetiteShape,
  extraAppetiteSlots,
  nextAppetitePlate,
  localDateISO,
  GAP_CONFIG,
  closeCheckIn,
  currentMealSlot,
  topUpGap,
  type Goal,
  type ScheduledCheckIn,
  type SlotName,
} from '../engine/index.js';
import { SCHEDULE_CONFIG } from '../engine/mealSchedule.js';
import { REFUEL_WINDOW_MIN } from '../engine/training.js';
import { trainingForLocalDay, workoutHomeRows } from '../training/day.js';
import type { ManagerVoice } from '../managerVoice/types.js';
import { toMealSummaries, type MealSummary } from '../meals/summary.js';
import type { PhotoStore } from '../photos/store.js';
import { homeFraming, type FramingState } from './classify.js';
import { buildDay, type DayView } from './day.js';
import { mealWindow } from '../managerVoice/fallback.js';
import { excludedTokensFor, loadStapleFoods, namedSummary, pickTopUp } from '../solver/index.js';

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
  /**
   * After a light meal: one or two calorie-dense add-ons that bring the day
   * back toward pace, ready to log in one tap. Null when on pace, in quiet
   * mode, or while a check-in is open.
   */
  topUp: null | {
    slot: SlotName;
    behindKcal: number;
    totalKcal: number;
    totalProteinG: number;
    /** What gets logged when the user taps Add. */
    logText: string;
    items: { name: string; servingDesc: string; quantity: number; kcal: number; proteinG: number; carbsG: number; fatG: number }[];
  };
  /** The evening close-the-gap check-in, if the day is still short at that time. Null in quiet mode. */
  closeCheckIn: { dueMin: number; gapKcal: number } | null;
  needsWeighIn: boolean;
  busyBlocks: { startMin: number; endMin: number }[];
  movedSlots: { slot: SlotName; fromMin: number; toMin: number }[];
  training: {
    bumpKcal: number;
    addCalories: boolean;
    workouts: {
      id: string;
      kind: string;
      source: string;
      startMin: number;
      durationMin: number;
      activeKcal: number | null;
    }[];
    refuelUntilMin: number | null;
  };
  appetite: {
    mode: string;
    level: string;
    drinkableOk: boolean;
    suggestSmallerDefault: boolean;
    answeredToday: boolean;
    askDaily: boolean;
    nextPlate: { slot: string; atMin: number; kcal: number } | null;
    extraSlots: { slot: string; atMin: number }[];
  };
  activeCheckIn: null | {
    id: string;
    tier: number;
        /** The meal it's about; null for a tier-3 conversation. */
    slot: SlotName | null;
        kind: string;
    variant: string;
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
    include: { onboarding: true, safetyScreening: true, escalationState: true, weightEntries: { orderBy: { measuredAt: 'desc' }, take: 1 } },
  });
  // A valid token for a deleted account — the app should sign out, not start onboarding.
  if (!user) throw new AccountNotFoundError('account not found');
  if (!user.onboarding) throw new OnboardingIncompleteError('onboarding not complete');

  const profile = user.onboarding;
  const dayStart = startOfLocalDay(now, user.timezone);

  const [todayMeals, lastMeal, activeCheckIn, todayCheckIns, lastWeighIn, busyRows, dayAppetite, smallerCount, keepRows] = await Promise.all([
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
        parseQuality: true,
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
      select: { createdAt: true, tier: true, slot: true, kind: true },
    }),
    prisma.weightEntry.findFirst({
      where: { userId },
      orderBy: { measuredAt: 'desc' },
      select: { measuredAt: true },
    }),
    prisma.calendarBusyBlock.findMany({
      where: { userId, end: { gt: dayStart }, start: { lt: new Date(dayStart.getTime() + 86_400_000) } },
      select: { start: true, end: true, allDay: true },
    }),
    prisma.dayAppetite.findUnique({
      where: { userId_localDate: { userId, localDate: localDateISO(now, user.timezone) } },
    }),
    prisma.checkIn.count({
      where: {
        userId,
        variant: 'smaller',
        createdAt: { gte: new Date(now.getTime() - 7 * 86_400_000) },
      },
    }),
    profile.calendarEnabled
      ? prisma.calendarKeep.findMany({
          where: { userId, localDate: localDateISO(now, user.timezone) },
          select: { slot: true },
        })
      : Promise.resolve([]),
  ]);

  const consumedKcal = todayMeals.reduce((acc, m) => acc + m.kcal, 0);
  const consumedProteinG = round1(todayMeals.reduce((acc, m) => acc + m.proteinG, 0));
  const addCalories = profile.trainingAddCalories ?? true;
  const weightKg = user.weightEntries[0]?.weightKg ?? profile.weightKg ?? 80;
  const trainingDay = await trainingForLocalDay(prisma, {
    userId,
    now,
    timezone: user.timezone,
    weightKg,
    baseKcal: profile.dailyKcalTarget,
    addCalories,
  });
  const targetKcal = trainingDay.targetKcal;
  const targetProteinG = profile.dailyProteinTargetG;
  const goal = profile.goal as Goal;

  const framing = homeFraming(goal, consumedKcal, targetKcal);
  const remainingKcal = Math.round(targetKcal - consumedKcal);
  const remainingProteinG = targetProteinG === null ? null : round1(targetProteinG - consumedProteinG);
  const hoursSinceMeal = lastMeal ? hoursBetween(lastMeal.loggedAt, now) : null;
  const localMinute = (date: Date): number => Math.floor(msSinceLocalMidnight(date, user.timezone) / 60_000);
  const mins = localMinute(now);
  const times = mealTimesOn(profile, localWeekday(now, user.timezone));
  const grace = profile.checkInGraceMin ?? SCHEDULE_CONFIG.graceMin;
  const enforcementEnabled = user.safetyScreening?.enforcementEnabled ?? false;
  const shape = appetiteShape(
    (profile.appetiteMode as 'NORMAL' | 'SMALL_FREQUENT') ?? 'NORMAL',
    (dayAppetite?.level as 'HUNGRY' | 'NORMAL' | 'LOW') ?? null,
  );
  const extraSlots = shape === 'SMALL';

  const day = buildDay({
    nowMin: mins,
    mealTimes: times,
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

  const calendarPrefs = prefsFromProfile(profile);
  const todayBusy = toMinuteBlocks(busyRows, dayStart, user.timezone);
  const weekday = localWeekday(now, user.timezone);
  const keptSlots = new Set(keepRows.map((k) => k.slot));
  const escalation = user.escalationState;

  const checksRunning =
    enforcementEnabled &&
    !escalation?.checkInsPaused &&
    !(escalation?.backedOffUntil && escalation.backedOffUntil > now) &&
    activeCheckIn === null;
  const checkedSlotsToday = todayCheckIns
    .filter(
      (c) => c.tier < TIER.CONVERSATION && c.kind !== 'REFUEL' && c.kind !== 'PRE_WORKOUT' && c.kind !== 'CLOSE',
    )
    .map((c) => slotNameOf(c.slot) ?? checkInSlotAt(localMinute(c.createdAt), times, grace))
    .filter((slot): slot is SlotName => slot !== null);
  const scheduled = checksRunning
    ? upcomingCheckIn({
        nowMin: mins,
        times,
        graceMin: grace,
        mealMinutesToday: todayMeals.map((m) => localMinute(m.loggedAt)),
        checkedSlotsToday,
        consumedKcal,
        targetKcal,
        extraSlots,
        lightRule: GAP_CONFIG,
      })
    : null;
  const shifted = scheduled?.light
    ? { ...scheduled, movedFromMin: null, busy: null }
    : scheduled
    ? withOverdue(applyCalendarShift(scheduled, times, todayBusy, calendarPrefs, weekday, keptSlots)!, mins)
    : null;
  const nextCheckIn =
    shifted && !isWithinQuietHours(shifted.dueMin, profile.quietHoursStartMin, profile.quietHoursEndMin)
      ? {
          slot: shifted.slot,
          mealMin: shifted.mealMin,
          dueMin: shifted.dueMin,
          overdue: shifted.overdue,
          ...(shifted.light ? { light: true } : {}),
        }
      : null;

  const lastCheckInAt = todayCheckIns.reduce<Date | null>(
    (acc, c) => (acc === null || c.createdAt > acc ? c.createdAt : acc),
    null,
  );
  const evening =
    checksRunning && (!nextCheckIn || nextCheckIn.slot !== 'dinner')
      ? closeCheckIn({
          nowMin: mins,
          times,
          quietStartMin: profile.quietHoursStartMin,
          consumedKcal,
          targetKcal,
          closedToday: todayCheckIns.some((c) => c.kind === 'CLOSE'),
          minSinceLastCheckIn: lastCheckInAt ? Math.floor((now.getTime() - lastCheckInAt.getTime()) / 60_000) : null,
        })
      : null;

  const slotNow = currentMealSlot(mins, times);
  const topUpNeed =
    enforcementEnabled && activeCheckIn === null
      ? topUpGap({
          currentSlot: slotNow,
          loggedInSlot: day.slots.some((s) => s.slot === slotNow && s.mealIds.length > 0),
          consumedKcal,
          targetKcal,
          extra: false,
        })
      : null;
  const topUpRx = topUpNeed
    ? pickTopUp((await loadStapleFoods(prisma)).solverFoods, {
        targetKcal: topUpNeed.topUpKcal,
        excludedTokens: await excludedTokensFor(prisma, userId, profile.dislikedFoods),
        drinkableOk: profile.drinkableOk ?? true,
      })
    : null;
  const busyBlocks = calendarPrefs.enabled
    ? qualifyingBusyBlocks(todayBusy, calendarPrefs, weekday).map((b) => ({
        startMin: b.startMin,
        endMin: b.endMin,
      }))
    : [];
  const movedSlots = movedSlotsToday(times, grace, todayBusy, calendarPrefs, weekday, keptSlots);
  const trainingRows = workoutHomeRows(trainingDay.workouts, user.timezone, dayStart);
  const firstSession = trainingDay.workouts[0];
  const refuelUntilMin = firstSession
    ? Math.floor(msSinceLocalMidnight(firstSession.start, user.timezone) / 60_000) +
      firstSession.durationMin +
      REFUEL_WINDOW_MIN
    : null;

  const nextPlate = nextAppetitePlate({
    nowMin: mins,
    times,
    shape,
    remainingKcal: Math.max(0, remainingKcal),
    checked: checkedSlotsToday,
    mealMinutesToday: todayMeals.map((m) => localMinute(m.loggedAt)),
  });

  const managerNote = await deps.voice.homeNote({
    goal,
    state: framing.state,
    consumedKcal,
    targetKcal,
    remainingKcal,
    remainingProteinG,
    mealsToday: todayMeals.length,
    nextMeal:
      day.pace?.next?.slot ?? mealWindow(mins, { lunchMin: times.lunchMin, dinnerMin: times.dinnerMin }),
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
    mealTimes: times,
    quietHours: { startMin: profile.quietHoursStartMin, endMin: profile.quietHoursEndMin },
    day,
    nextCheckIn,
    topUp:
      topUpNeed && topUpRx
        ? {
            slot: topUpNeed.slot,
            behindKcal: topUpNeed.behindKcal,
            totalKcal: topUpRx.totalKcal,
            totalProteinG: topUpRx.totalProteinG,
            logText: `Top-up: ${namedSummary(topUpRx)}`,
            items: topUpRx.items.map((i) => ({
              name: i.name,
              servingDesc: i.servingDesc,
              quantity: i.quantity,
              kcal: i.kcal,
              proteinG: i.proteinG,
              carbsG: i.carbsG,
              fatG: i.fatG,
            })),
          }
        : null,
    closeCheckIn: evening && !evening.overdue ? { dueMin: evening.dueMin, gapKcal: evening.gapKcal } : null,
    busyBlocks,
    movedSlots,
    training: {
      bumpKcal: addCalories ? trainingDay.bump : 0,
      addCalories,
      workouts: trainingRows,
      refuelUntilMin,
    },
    appetite: {
      mode: profile.appetiteMode ?? 'NORMAL',
      level: dayAppetite?.level ?? (shape === 'SMALL' ? 'LOW' : 'NORMAL'),
      drinkableOk: profile.drinkableOk ?? true,
      suggestSmallerDefault: smallerCount >= 2,
      answeredToday: dayAppetite !== null,
      askDaily: profile.appetiteAskDaily ?? true,
      nextPlate,
      extraSlots: extraSlots ? extraAppetiteSlots(times).map((s) => ({ slot: s.slot, atMin: s.mealMin })) : [],
    },
    needsWeighIn:
      goal !== 'MAINTAIN' &&
      (!lastWeighIn || now.getTime() - lastWeighIn.measuredAt.getTime() > 7 * 24 * 3_600_000),
    activeCheckIn: activeCheckIn
      ? {
          id: activeCheckIn.id,
          tier: activeCheckIn.tier,
          slot:
            activeCheckIn.tier < TIER.CONVERSATION
              ? slotNameOf(activeCheckIn.slot) ??
                checkInSlotAt(localMinute(activeCheckIn.createdAt), times, grace)
              : null,
          kind: activeCheckIn.kind,
          variant: activeCheckIn.variant,
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
