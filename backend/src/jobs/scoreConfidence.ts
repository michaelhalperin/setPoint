import type { Prisma, PrismaClient } from '@prisma/client';
import { fallbackTierThree } from '../ai/tierThree.js';
import { clock24, langOf, slotNameHe, type Lang } from '../i18n/index.js';
import { env } from '../env.js';
import {
  checkEligibility,
  checkInSlotAt,
  computeBehaviorScore,
  SCORE_CONFIG,
  decideEscalation,
  deriveHoursSinceMeal,
  expectedGapHours,
  freshCheckInTier,
  headsUpCopy,
  isBiosignalFresh,
  localDateISO,
  localWeekday,
  mealTimesOn,
  msSinceLocalMidnight,
  prefsFromProfile,
  slotNameOf,
  startOfLocalDay,
  TIER,
  toMinuteBlocks,
  upcomingCheckIn,
  applyCalendarShift,
  withOverdue,
  userInWearableCohort,
  wearableModifierKillSwitchOn,
  appetiteShape,
  extraAppetiteSlots,
  remainingSlotCount,
  appetiteMealTarget,
  needsRefuel,
  needsPreWorkoutNudge,
  effectiveWorkouts,
  GAP_CONFIG,
  countsAsMeal,
  SCHEDULE_CONFIG,
  closeCheckIn,
  dailyCapReached,
  lightShortfall,
  type EscalationDecision,
  type Goal,
  type SlotName,
} from '../engine/index.js';
import { evaluateStopConditions } from '../engine/stopConditions.js';
import { checkInCopy } from '../managerVoice/checkInCopy.js';
import { gatherStopSignals } from '../metrics/stopSignals.js';
import type { ManagerVoice } from '../managerVoice/types.js';
import { captureError } from '../observability/sentry.js';
import { deliverCheckIn } from '../push/deliver.js';
import type { PushSender } from '../push/types.js';
import {
  computePrescriptionTarget,
  excludedTokensFrom,
  loadStapleFoods,
  prescribe,
  prescriptionSummary,
  namedSummary,
  refuelPrescription,
  type PrescriptionResult,
  type SolverFood,
} from '../solver/index.js';
import { REFUEL_TARGET_PROTEIN_G } from '../solver/meals.js';
import { prescriptionFromSavedMeal } from '../savedMeals/index.js';
import { trainingForLocalDay } from '../training/day.js';
import { isFlagOnForUser } from '../flags/index.js';
import { isEntitled, subscriptionGateOn } from '../subscription/entitlement.js';

export type ScoreConfidenceDeps = {
  prisma: PrismaClient;
  push: PushSender;
  voice: ManagerVoice;
  now?: Date;
};

export type ScoreConfidenceSummary = {
  ranAt: string;
  usersEvaluated: number;
  scored: number;
  checkInsCreated: number;
  checkInsRedelivered: number;
  checkInsResolved: number;
  prescriptionsCreated: number;
  misses: number;
  tier3Started: number;
  errors: number;
  /** The wearable modifier was on but stop conditions switched it off for this run. */
  wearableHalted: boolean;
  skipped: Record<string, number>;
  /** Per person, in plain words: what this run did for them, or why it did nothing. Shown on their ops page. */
  reasons: Record<string, string>;
};

const USER_INCLUDE = {
  onboarding: true,
  safetyScreening: true,
  escalationState: true,
  biosignalState: true,
} satisfies Prisma.UserInclude;

type UserWithRelations = Prisma.UserGetPayload<{ include: typeof USER_INCLUDE }>;

type JobContext = {
  solverFoods: SolverFood[];
  foodIdBySlug: Map<string, string>;
  /** Stop conditions tripped: every user scores as Basic this run. */
  wearableHalted: boolean;
};

/**
 * The server-driven confidence job. Per onboarded user, in batches:
 *   1. advance any open check-in through the defer/escalation state machine,
 *   2. if nothing is pending and the user is eligible, check the meal schedule,
 *   3. score overdue slots with a versioned behavior formula (wearable = modifier),
 *   4. create a check-in + prescription and deliver (deterministic copy on the path).
 */
export async function runScoreConfidenceJob(
  deps: ScoreConfidenceDeps,
): Promise<ScoreConfidenceSummary> {
  const now = deps.now ?? new Date();
  const summary: ScoreConfidenceSummary = {
    ranAt: now.toISOString(),
    usersEvaluated: 0,
    scored: 0,
    checkInsCreated: 0,
    checkInsRedelivered: 0,
    checkInsResolved: 0,
    prescriptionsCreated: 0,
    misses: 0,
    tier3Started: 0,
    errors: 0,
    wearableHalted: false,
    skipped: {},
    reasons: {},
  };

  const context: JobContext = {
    ...(await loadStapleFoods(deps.prisma)),
    wearableHalted: await wearableHaltedByStopConditions(deps.prisma, now),
  };
  summary.wearableHalted = context.wearableHalted;

  const batchSize = env.SCORE_BATCH_SIZE;
  let cursor: string | undefined;
  for (;;) {
    const users = await deps.prisma.user.findMany({
      where: { onboarding: { isNot: null }, ...(cursor ? { id: { gt: cursor } } : {}) },
      orderBy: { id: 'asc' },
      take: batchSize,
      include: USER_INCLUDE,
    });
    if (users.length === 0) break;
    summary.usersEvaluated += users.length;
    for (const user of users) {
      try {
        await processUser(deps, context, user, now, summary);
      } catch (err) {
        summary.errors += 1;
        console.error(`scoreConfidence: user ${user.id} failed`, err);
        captureError(err, { userId: user.id, tags: { job: 'score' } });
      }
    }
    cursor = users[users.length - 1]!.id;
    if (users.length < batchSize) break;
  }

  return summary;
}

function bump(summary: ScoreConfidenceSummary, reason: string): void {
  summary.skipped[reason] = (summary.skipped[reason] ?? 0) + 1;
}

/** Remember, per person, what this run did or why it didn't. */
function note(summary: ScoreConfidenceSummary, userId: string, text: string): void {
  summary.reasons[userId] = text;
}

/** A check-in that never reached the phone is retried for this long, then given up on (not a miss). */
export const DELIVERY_RETRY_WINDOW_MIN = 90;

const ELIGIBILITY_WORDS: Record<string, string> = {
  onboarding_incomplete: 'Setup is not finished',
  enforcement_disabled: 'Check-ins are off for this person (safety screening)',
  checkins_paused: 'Check-ins are paused',
  backed_off: 'Backing off for a day after a run of missed check-ins',
  active_checkin: 'A check-in is already open',
  quiet_hours: 'Quiet hours',
};

function categoryOf(kind: string): 'CHECK_IN' | 'HEADS_UP' | 'REFUEL' {
  return kind === 'HEADS_UP' ? 'HEADS_UP' : kind === 'REFUEL' ? 'REFUEL' : 'CHECK_IN';
}

function escStateOf(user: UserWithRelations): { consecutiveMisses: number; currentTier: number } {
  return {
    consecutiveMisses: user.escalationState?.consecutiveMisses ?? 0,
    currentTier: user.escalationState?.currentTier ?? 1,
  };
}

const localMinute = (date: Date, timeZone: string): number =>
  Math.floor(msSinceLocalMidnight(date, timeZone) / 60_000);

async function processUser(
  deps: ScoreConfidenceDeps,
  ctx: JobContext,
  user: UserWithRelations,
  now: Date,
  summary: ScoreConfidenceSummary,
): Promise<void> {
  const profile = user.onboarding;
  if (!profile) return;
  const lang = langOf(user.language);

  const { prisma } = deps;
  const dayStart = startOfLocalDay(now, user.timezone);

  const [activeCheckIns, lastMeal, todayMeals, todayCheckIns, restrictions, usualForSlot, busyRows, workouts] = await Promise.all([
    prisma.checkIn.findMany({
      where: { userId: user.id, status: { in: ['PENDING', 'DEFERRED'] } },
      orderBy: { createdAt: 'desc' },
    }),
    prisma.meal.findFirst({
      where: { userId: user.id, kcal: { gte: SCHEDULE_CONFIG.minMealKcal } },
      orderBy: { loggedAt: 'desc' },
    }),
    prisma.meal.findMany({
      where: { userId: user.id, loggedAt: { gte: dayStart } },
      select: { kcal: true, proteinG: true, loggedAt: true },
    }),
    prisma.checkIn.findMany({
      where: { userId: user.id, createdAt: { gte: dayStart } },
      select: { createdAt: true, tier: true, episodeKey: true, slot: true, kind: true },
    }),
    prisma.dietaryRestriction.findMany({ where: { userId: user.id, isHardExclusion: true } }),
    prisma.savedMeal.findMany({
      where: { userId: user.id, useInCheckIns: true },
      orderBy: [{ lastUsedAt: 'desc' }, { useCount: 'desc' }],
    }),
    prisma.calendarBusyBlock.findMany({
      where: {
        userId: user.id,
        end: { gt: dayStart },
        start: { lt: new Date(dayStart.getTime() + 86_400_000) },
      },
      select: { start: true, end: true, allDay: true },
    }),
    prisma.workout.findMany({
      where: {
        userId: user.id,
        start: { gte: new Date(dayStart.getTime() - 86_400_000) },
      },
      orderBy: { start: 'asc' },
    }),
  ]);

  const consumedKcal = todayMeals.reduce((acc, m) => acc + m.kcal, 0);
  const training = await trainingForLocalDay(prisma, {
    userId: user.id,
    now,
    timezone: user.timezone,
    weightKg: profile.weightKg ?? 80,
    baseKcal: profile.dailyKcalTarget,
    addCalories: profile.trainingAddCalories ?? true,
  });
  const targetKcal = training.targetKcal;
  const underTarget = consumedKcal < targetKcal;

  let blocked = false;
  let droppedNow = 0;
  for (const ci of activeCheckIns) {
    // A check-in whose push never went out (no token yet, APNs hiccup) must not sit silent for hours:
    // try again every run for a while, then let it go so a fresh one can take its place.
    if (ci.status === 'PENDING' && (ci.deliveryStatus === 'FAILED' || ci.deliveryStatus === 'CREATED')) {
      const ageMin = (now.getTime() - ci.createdAt.getTime()) / 60_000;
      if (ageMin >= DELIVERY_RETRY_WINDOW_MIN) {
        await prisma.checkIn.update({ where: { id: ci.id }, data: { status: 'EXPIRED', resolvedAt: now } });
        summary.checkInsResolved += 1;
        droppedNow += 1;
        note(summary, user.id, `A check-in never reached the phone (${ci.lastPushError ?? 'not sent'}) and was dropped after ${DELIVERY_RETRY_WINDOW_MIN} min`);
        continue;
      }
      const rx = await prisma.prescription.findFirst({ where: { checkInId: ci.id }, select: { id: true } });
      await markDelivered(deps, user.id, ci.id, ci.tier, ci.message ?? 'Time to eat.', rx?.id ?? null, now, categoryOf(ci.kind));
      summary.checkInsRedelivered += 1;
      note(summary, user.id, `Tried again to send an undelivered check-in (${ci.lastPushError ?? 'not sent'})`);
      blocked = true;
      continue;
    }
    const isDeferred = ci.status === 'DEFERRED';
    const decision = decideEscalation({
      checkIn: {
        status: isDeferred ? 'DEFERRED' : 'PENDING',
        tier: ci.tier,
        deferCount: ci.deferCount,
        deliveredAt: ci.deliveredAt ?? ci.createdAt,
        deferUntil: ci.deferUntil,
        deliveryStatus: ci.deliveryStatus,
      },
      state: escStateOf(user),
      stillDue: isDeferred ? underTarget : null,
      now,
    });
    // The evening close is an offer, not a meal: letting it lapse never counts as a miss.
    const settled =
      ci.kind === 'CLOSE' && (decision.kind === 'miss' || decision.kind === 'redeliver')
        ? ({ kind: 'resolve' } as EscalationDecision)
        : decision;
    blocked = (await applyDecision(deps, user, ci.id, ci.message, settled, now, summary)) || blocked;
  }

  if (blocked || activeCheckIns.length - droppedNow > 0) {
    bump(summary, 'active_checkin');
    if (!summary.reasons[user.id]) {
      const open = activeCheckIns[0];
      note(summary, user.id, open ? `A check-in is already open (${String(open.kind ?? 'meal').toLowerCase()}, ${open.status.toLowerCase()})` : 'A check-in is already open');
    }
    return;
  }

  const eligibility = checkEligibility({
    now,
    timezone: user.timezone,
    onboardingCompleted: profile.completedAt !== null,
    enforcementEnabled: user.safetyScreening?.enforcementEnabled ?? false,
    checkInsPaused: user.escalationState?.checkInsPaused ?? false,
    backedOffUntil: user.escalationState?.backedOffUntil ?? null,
    quietHoursStartMin: profile.quietHoursStartMin,
    quietHoursEndMin: profile.quietHoursEndMin,
    hasActiveCheckIn: false,
  });
  if (!eligibility.eligible) {
    bump(summary, eligibility.reason);
    note(summary, user.id, ELIGIBILITY_WORDS[eligibility.reason] ?? eligibility.reason);
    return;
  }

  if (dailyCapReached(todayCheckIns)) {
    bump(summary, 'daily_cap');
    note(summary, user.id, `Already sent ${GAP_CONFIG.maxCheckInsPerDay} check-ins today`);
    return;
  }

  // Meal and close-the-gap check-ins are free — they're the product. A
  // subscription adds training check-ins and calendar-aware timing, only when
  // both SUBSCRIPTION_GATE and the paywall flag are on for this user.
  const entitled = isEntitled(
    user,
    now,
    subscriptionGateOn() && (await isFlagOnForUser(prisma, user.id, 'paywall')),
  );

  if (
    entitled &&
    await maybeFireTrainingCheckIn(deps, user, {
      now,
      dayStart,
      todayMeals,
      todayCheckIns,
      workouts,
      dinnerMin: mealTimesOn(profile, localWeekday(now, user.timezone)).dinnerMin,
      restrictions,
      usualForSlot,
      solverFoods: ctx.solverFoods,
      foodIdBySlug: ctx.foodIdBySlug,
      summary,
    })
  ) {
    note(summary, user.id, 'Sent a training check-in');
    return;
  }

  const times = mealTimesOn(profile, localWeekday(now, user.timezone));
  const nowMin = localMinute(now, user.timezone);
  const dayAppetite = await prisma.dayAppetite.findUnique({
    where: { userId_localDate: { userId: user.id, localDate: localDateISO(now, user.timezone) } },
  });
  const shape = appetiteShape(
    (profile.appetiteMode as 'NORMAL' | 'SMALL_FREQUENT') ?? 'NORMAL',
    (dayAppetite?.level as 'HUNGRY' | 'NORMAL' | 'LOW') ?? null,
  );
  const extraSlots = shape === 'SMALL';
  const checkedSlotsToday = todayCheckIns
    .filter(
      (c) => c.tier < TIER.CONVERSATION && c.kind !== 'REFUEL' && c.kind !== 'PRE_WORKOUT' && c.kind !== 'CLOSE',
    )
    .map((c) => slotNameOf(c.slot) ?? checkInSlotAt(localMinute(c.createdAt, user.timezone), times, profile.checkInGraceMin))
    .filter((slot): slot is SlotName => slot !== null);
  const upcoming = upcomingCheckIn({
    nowMin,
    times,
    graceMin: profile.checkInGraceMin,
    mealMinutesToday: todayMeals.filter((m) => countsAsMeal(m.kcal)).map((m) => localMinute(m.loggedAt, user.timezone)),
    checkedSlotsToday,
    consumedKcal,
    targetKcal,
    extraSlots,
    lightRule: GAP_CONFIG,
  });
  const calendarPrefs = entitled ? prefsFromProfile(profile) : { ...prefsFromProfile(profile), enabled: false };
  const todayBusy = toMinuteBlocks(busyRows, dayStart, user.timezone);
  const keepRows = calendarPrefs.enabled
    ? await prisma.calendarKeep.findMany({
        where: { userId: user.id, localDate: localDateISO(now, user.timezone) },
        select: { slot: true },
      })
    : [];
  // A light meal was eaten; moving its follow-up around the calendar makes no sense.
  const shifted = upcoming?.light
    ? { ...upcoming, movedFromMin: null, busy: null }
    : upcoming
    ? withOverdue(
        applyCalendarShift(
          upcoming,
          times,
          todayBusy,
          calendarPrefs,
          localWeekday(now, user.timezone),
          new Set(keepRows.map((k) => k.slot)),
        )!,
        nowMin,
      )
    : null;
  const due = shifted?.overdue ? shifted : null;
  summary.scored += 1;
  if (!due) {
    if (
      shifted?.slot !== 'dinner' &&
      (await maybeFireCloseCheckIn(deps, user, {
        now,
        nowMin,
        times,
        consumedKcal,
        targetKcal,
        consumedProteinG: todayMeals.reduce((acc, m) => acc + m.proteinG, 0),
        todayCheckIns,
        restrictions,
        solverFoods: ctx.solverFoods,
        foodIdBySlug: ctx.foodIdBySlug,
        summary,
      }))
    ) {
      note(summary, user.id, 'Sent the evening check-in');
      return;
    }
    bump(summary, 'not_due');
    const small = todayMeals.filter((m) => !countsAsMeal(m.kcal)).length;
    const ignored = small > 0 ? `; ${small} small log${small > 1 ? 's' : ''} under ${SCHEDULE_CONFIG.minMealKcal} kcal don't count as a meal` : '';
    note(
      summary,
      user.id,
      (shifted
        ? `Nothing due yet: next is ${shifted.slot.replace('_', ' ')} at ${clock24(shifted.dueMin)}`
        : consumedKcal >= targetKcal
          ? 'Nothing due: today\'s target is met'
          : 'Nothing due: every meal today is covered or past') + ignored,
    );
    return;
  }

  const episodeKey = `${localDateISO(now, user.timezone)}:${due.slot}`;
  const existing = todayCheckIns.find((c) => c.episodeKey === episodeKey);
  if (existing) {
    bump(summary, 'duplicate_episode');
    note(summary, user.id, `Already checked in for ${due.slot.replace('_', ' ')} today`);
    return;
  }

  const hoursSinceMeal = deriveHoursSinceMeal(lastMeal?.loggedAt ?? null, user.createdAt, now);
  const wearableFresh =
    profile.mode === 'SMART' &&
    user.biosignalState &&
    isBiosignalFresh(user.biosignalState.updatedAt, now)
      ? user.biosignalState
      : null;
  const wearableEnabled = !ctx.wearableHalted && userInWearableCohort(user.id, user.wearableModifierEnabled);
  // How this same meal's recent check-ins went — "already ate" / "wrong time" holds it back.
  const slotCheckIns = await prisma.checkIn.findMany({
    where: { userId: user.id, slot: due.slot, tier: { lt: TIER.CONVERSATION } },
    orderBy: { createdAt: 'desc' },
    take: SCORE_CONFIG.slotHistory,
    select: { status: true, feedbackPositive: true },
  });
  const overdueMin = Math.max(0, localMinute(now, user.timezone) - due.dueMin);
  const scored = computeBehaviorScore({
    slot: due.slot,
    overdueMin,
    hoursSinceMeal,
    expectedGapHours: expectedGapHours(due.slot, times),
    consumedKcal,
    targetKcal,
    slotCheckIns,
    wearable: wearableFresh
      ? { hrvDeviation: wearableFresh.hrvDeviation, rhrDeviation: wearableFresh.rhrDeviation }
      : null,
    wearableEnabled,
  });

  // One audit row per meal episode, refreshed each run until it fires — not a
  // new row every 15 minutes while a meal is held.
  const scoreData = {
    computedAt: now,
    mode: profile.mode,
    score: scored.score,
    scoringVersion: scored.version,
    behaviorScore: scored.behaviorScore,
    wearableModifier: scored.wearableModifier,
    wearableUsed: scored.wearableUsed,
    biosignalDeviation: wearableFresh?.hrvDeviation ?? null,
    hoursSinceMeal,
    expectedGapHours: expectedGapHours(due.slot, times),
    loggingSilence: null,
    overdueMin,
    dismissRate: scored.components.slotDismissRate,
    targetCoverage: scored.components.consumedShare,
    components: scored.components,
    threshold: scored.threshold,
    firedCheckIn: scored.shouldFire,
  };
  const score = await prisma.confidenceScore.upsert({
    where: { userId_episodeKey: { userId: user.id, episodeKey } },
    create: { userId: user.id, episodeKey, ...scoreData },
    update: scoreData,
  });

  if (!scored.shouldFire) {
    bump(summary, 'below_threshold');
    note(
      summary,
      user.id,
      `${due.slot.replace('_', ' ')} is ${Math.round(overdueMin)} min overdue, holding: score ${scored.score.toFixed(2)} of ${scored.threshold.toFixed(2)}`,
    );
    return;
  }

  const excludedTokens = excludedTokensFrom(restrictions, profile.dislikedFoods);
  const pantry = profile.pantryTokens ?? [];

  const tier = freshCheckInTier(escStateOf(user));
  const remainingSlots = remainingSlotCount({
    nowMin,
    times,
    extra: extraSlots,
    checked: checkedSlotsToday,
    mealMinutesToday: todayMeals.filter((m) => countsAsMeal(m.kcal)).map((m) => localMinute(m.loggedAt, user.timezone)),
  });
  const computed = computePrescriptionTarget({
    dailyKcalTarget: targetKcal,
    consumedKcal,
    dailyProteinTargetG: profile.dailyProteinTargetG,
    consumedProteinG: todayMeals.reduce((acc, m) => acc + m.proteinG, 0),
  });
  const isLight = due.light === true;
  const shapedKcal = isLight
    ? lightShortfall({ slot: due.slot, consumedKcal, targetKcal, extra: extraSlots })
    : shape === 'NORMAL'
      ? computed.targetKcal
      : appetiteMealTarget({
          remainingKcal: Math.max(0, targetKcal - consumedKcal),
          remainingSlots,
          shape,
        });
  const target = { targetKcal: shapedKcal, targetProteinG: computed.targetProteinG };

  const usual =
    due.slot === 'snack_am' || due.slot === 'snack_pm'
      ? null
      : (usualForSlot.find((m) => m.suggestSlot === due.slot) ?? null);
  const rx = usual
    ? prescriptionFromSavedMeal(usual, target)
    : ctx.solverFoods.length > 0
      ? prescribe(ctx.solverFoods, {
          targetKcal: target.targetKcal,
          targetProteinG: target.targetProteinG,
          excludedTokens,
          preferLowFriction: tier >= 2 || shape === 'SMALL',
          pantryTokens: pantry,
          prepTimeMaxMin: profile.prepTimeMaxMin,
          preferCalorieDense: shape === 'SMALL',
          preferDrinkable: shape === 'SMALL' && (profile.drinkableOk ?? true),
        })
      : null;
  const summaryLine = rx ? prescriptionSummary(rx, lang) : null;
  const namedLine = rx ? namedSummary(rx, lang) : null;
  const isHeadsUp = due.movedFromMin != null && due.busy != null;
  const message = isHeadsUp && due.busy
    ? headsUpCopy(due.busy, due.slot, lang)
    : isLight
    ? lightMealCopy(due.slot, namedLine, lang)
    : checkInCopy({
        tier,
        goal: profile.goal as Goal,
        hoursSinceMeal: lastMeal ? hoursSinceMeal : null,
        kcalGap: target.targetKcal,
        prescriptionSummary: summaryLine,
        slot: due.slot,
        lang,
      });

  const busyUntil =
    isHeadsUp && due.busy
      ? new Date(dayStart.getTime() + due.busy.endMin * 60_000)
      : null;

  const checkIn = await prisma.checkIn.create({
    data: {
      userId: user.id,
      confidenceScoreId: score.id,
      tier,
      status: 'PENDING',
      deliveryStatus: 'CREATED',
      message,
      slot: due.slot,
      episodeKey,
      kind: isHeadsUp ? 'HEADS_UP' : isLight ? 'TOP_UP' : 'MEAL',
      movedFromMin: due.movedFromMin,
      busyUntil,
    },
  });

  let prescriptionId: string | null = null;
  if (rx) {
    const created = await prisma.prescription.create({
      data: {
        userId: user.id,
        checkInId: checkIn.id,
        targetKcal: rx.targetKcal,
        targetProteinG: rx.targetProteinG,
        totalKcal: rx.totalKcal,
        totalProteinG: rx.totalProteinG,
        totalCarbsG: rx.totalCarbsG,
        totalFatG: rx.totalFatG,
        status: 'OFFERED',
        items: {
          create: rx.items.map((i) => ({
            foodItemId: ctx.foodIdBySlug.get(i.slug) ?? null,
            name: i.name,
            quantity: i.quantity,
            unit: 'serving',
            kcal: i.kcal,
            proteinG: i.proteinG,
            carbsG: i.carbsG,
            fatG: i.fatG,
          })),
        },
      },
    });
    prescriptionId = created.id;
    summary.prescriptionsCreated += 1;
  }

  await markDelivered(deps, user.id, checkIn.id, tier, message, prescriptionId, now, isHeadsUp ? 'HEADS_UP' : 'CHECK_IN');
  const sent = await prisma.checkIn.findUnique({ where: { id: checkIn.id }, select: { deliveryStatus: true, lastPushError: true } });
  note(
    summary,
    user.id,
    sent?.deliveryStatus === 'SENT'
      ? `Sent a ${due.slot.replace('_', ' ')} check-in`
      : `Created a ${due.slot.replace('_', ' ')} check-in but the push did not go out (${sent?.lastPushError ?? 'unknown'})`,
  );
  await prisma.escalationState.upsert({
    where: { userId: user.id },
    create: { userId: user.id, lastCheckInAt: now, currentTier: tier },
    update: { lastCheckInAt: now },
  });
  summary.checkInsCreated += 1;
}

/** Deterministic: the numbers in it must match the plate exactly. */
export function lightMealCopy(slot: SlotName, summaryLine: string | null, lang: Lang = 'en'): string {
  if (lang === 'he') {
    const meal = slotNameHe(slot);
    const was = meal === 'הנשנוש' ? 'היה קל' : 'הייתה קלה';
    return summaryLine
      ? `${meal} ${was}. הוסף ${summaryLine} כדי להישאר בקצב.`
      : `${meal} ${was}. עוד קצת עכשיו שומר על הקצב של היום.`;
  }
  const meal = slot === 'snack_am' || slot === 'snack_pm' ? 'That snack' : slot[0]!.toUpperCase() + slot.slice(1);
  return summaryLine
    ? `${meal} was light. Add ${summaryLine[0]!.toLowerCase()}${summaryLine.slice(1)} to stay on pace.`
    : `${meal} was light. A little more now keeps the day on pace.`;
}

export function closeCopy(gapKcal: number, summaryLine: string | null, lang: Lang = 'en'): string {
  const gap = Math.round(gapKcal / 10) * 10;
  if (lang === 'he') {
    return summaryLine
      ? `חסרות לך ${gap} קלוריות היום. ${summaryLine} סוגר את רוב זה.`
      : `חסרות לך ${gap} קלוריות היום. משהו קל לפני השינה יסגור את זה.`;
  }
  return summaryLine
    ? `You're ${gap} kcal short today. ${summaryLine[0]!.toUpperCase()}${summaryLine.slice(1)} closes most of it.`
    : `You're ${gap} kcal short today. Something easy before bed closes it.`;
}

type CloseCtx = {
  now: Date;
  nowMin: number;
  times: { breakfastMin: number; lunchMin: number; dinnerMin: number };
  consumedKcal: number;
  targetKcal: number;
  consumedProteinG: number;
  todayCheckIns: { episodeKey: string | null; kind: string; tier: number; createdAt: Date }[];
  restrictions: { token: string }[];
  solverFoods: SolverFood[];
  foodIdBySlug: Map<string, string>;
  summary: ScoreConfidenceSummary;
};

/** The evening close-the-gap check-in (once a day, after dinner had its chance). */
async function maybeFireCloseCheckIn(
  deps: ScoreConfidenceDeps,
  user: UserWithRelations,
  ctx: CloseCtx,
): Promise<boolean> {
  const profile = user.onboarding;
  if (!profile) return false;
  const last = ctx.todayCheckIns.reduce<Date | null>(
    (acc, c) => (acc === null || c.createdAt > acc ? c.createdAt : acc),
    null,
  );
  const close = closeCheckIn({
    nowMin: ctx.nowMin,
    times: ctx.times,
    quietStartMin: profile.quietHoursStartMin,
    consumedKcal: ctx.consumedKcal,
    targetKcal: ctx.targetKcal,
    closedToday: ctx.todayCheckIns.some((c) => c.kind === 'CLOSE'),
    minSinceLastCheckIn: last ? Math.floor((ctx.now.getTime() - last.getTime()) / 60_000) : null,
  });
  if (!close?.overdue) return false;
  const episodeKey = `${localDateISO(ctx.now, user.timezone)}:close`;
  if (ctx.todayCheckIns.some((c) => c.episodeKey === episodeKey)) return false;

  const remainingProtein =
    profile.dailyProteinTargetG != null ? Math.max(0, profile.dailyProteinTargetG - ctx.consumedProteinG) : null;
  const rx =
    ctx.solverFoods.length > 0
      ? prescribe(ctx.solverFoods, {
          targetKcal: close.plateKcal,
          targetProteinG: remainingProtein != null ? Math.min(remainingProtein, REFUEL_TARGET_PROTEIN_G) : null,
          excludedTokens: excludedTokensFrom(ctx.restrictions, profile.dislikedFoods),
          preferLowFriction: true,
          preferCalorieDense: true,
          preferDrinkable: profile.drinkableOk ?? true,
          pantryTokens: profile.pantryTokens ?? [],
        })
      : null;
  const message = closeCopy(close.gapKcal, rx ? namedSummary(rx, langOf(user.language)) : null, langOf(user.language));
  const checkIn = await deps.prisma.checkIn.create({
    data: {
      userId: user.id,
      tier: 1,
      status: 'PENDING',
      deliveryStatus: 'CREATED',
      message,
      slot: 'close',
      episodeKey,
      kind: 'CLOSE',
    },
  });
  const prescriptionId = rx ? await savePrescription(deps.prisma, user.id, checkIn.id, rx, ctx.foodIdBySlug) : null;
  if (prescriptionId) ctx.summary.prescriptionsCreated += 1;
  await markDelivered(deps, user.id, checkIn.id, 1, message, prescriptionId, ctx.now, 'CHECK_IN');
  await deps.prisma.escalationState.upsert({
    where: { userId: user.id },
    create: { userId: user.id, lastCheckInAt: ctx.now, currentTier: 1 },
    update: { lastCheckInAt: ctx.now },
  });
  ctx.summary.checkInsCreated += 1;
  return true;
}

async function savePrescription(
  prisma: PrismaClient,
  userId: string,
  checkInId: string,
  rx: PrescriptionResult,
  foodIdBySlug: Map<string, string>,
): Promise<string> {
  const created = await prisma.prescription.create({
    data: {
      userId,
      checkInId,
      targetKcal: rx.targetKcal,
      targetProteinG: rx.targetProteinG,
      totalKcal: rx.totalKcal,
      totalProteinG: rx.totalProteinG,
      totalCarbsG: rx.totalCarbsG,
      totalFatG: rx.totalFatG,
      status: 'OFFERED',
      items: {
        create: rx.items.map((i) => ({
          foodItemId: foodIdBySlug.get(i.slug) ?? null,
          name: i.name,
          quantity: i.quantity,
          unit: 'serving',
          kcal: i.kcal,
          proteinG: i.proteinG,
          carbsG: i.carbsG,
          fatG: i.fatG,
        })),
      },
    },
  });
  return created.id;
}

type TrainingCtx = {
  now: Date;
  dayStart: Date;
  todayMeals: { kcal: number; proteinG: number; loggedAt: Date }[];
  todayCheckIns: { episodeKey: string | null; kind: string; slot: string | null; tier: number; createdAt: Date }[];
  workouts: { id: string; source: string; start: Date; durationMin: number; outcome?: string | null }[];
  dinnerMin: number;
  restrictions: { token: string }[];
  usualForSlot: { suggestSlot: string | null }[];
  solverFoods: SolverFood[];
  foodIdBySlug: Map<string, string>;
  summary: ScoreConfidenceSummary;
};

async function maybeFireTrainingCheckIn(
  deps: ScoreConfidenceDeps,
  user: UserWithRelations,
  ctx: TrainingCtx,
): Promise<boolean> {
  const profile = user.onboarding;
  if (!profile) return false;
  const enforcement = user.safetyScreening?.enforcementEnabled ?? false;
  const meals = ctx.todayMeals.map((m) => ({ at: m.loggedAt, kcal: m.kcal }));
  const excludedTokens = excludedTokensFrom(ctx.restrictions, profile.dislikedFoods);

  // Only a session Apple Health recorded, or a planned one they confirmed, proves
  // the user trained — an unanswered plan may have been skipped.
  for (const workout of ctx.workouts.filter((w) => w.source === 'HEALTHKIT' || w.outcome === 'DONE')) {
    const ended = new Date(workout.start.getTime() + workout.durationMin * 60_000);
    if (
      !needsRefuel({
        workoutEndedAt: ended,
        now: ctx.now,
        meals,
        enforcementEnabled: enforcement,
      })
    ) {
      continue;
    }
    const episodeKey = `${localDateISO(ctx.now, user.timezone)}:refuel:${workout.id}`;
    if (ctx.todayCheckIns.some((c) => c.episodeKey === episodeKey)) continue;
    const lang = langOf(user.language);
    const dinner = lang === 'he' ? clock24(ctx.dinnerMin) : formatClock(ctx.dinnerMin);
    await createTrainingCheckIn(deps, user, {
      now: ctx.now,
      episodeKey,
      kind: 'REFUEL',
      slot: 'refuel',
      workoutId: workout.id,
      message:
        lang === 'he'
          ? `התאמנת. תאכל משהו עכשיו — ארוחת הערב ב-${dinner} יכולה לכסות את זה.`
          : `You trained. Eat something now — dinner at ${dinner} can cover it.`,
      category: 'REFUEL',
      rx: refuelPrescription(ctx.solverFoods, excludedTokens),
      foodIdBySlug: ctx.foodIdBySlug,
      summary: ctx.summary,
    });
    return true;
  }

  const nudgeMin = profile.preWorkoutNudgeMin ?? null;
  for (const workout of effectiveWorkouts(ctx.workouts).filter((w) => w.source === 'PLANNED')) {
    if (
      !needsPreWorkoutNudge({
        plannedStart: workout.start,
        now: ctx.now,
        meals: meals.map((m) => ({ at: m.at })),
        nudgeMin,
        enforcementEnabled: enforcement,
      })
    ) {
      continue;
    }
    const episodeKey = `${localDateISO(ctx.now, user.timezone)}:preworkout:${workout.id}`;
    if (ctx.todayCheckIns.some((c) => c.episodeKey === episodeKey)) continue;
    await createTrainingCheckIn(deps, user, {
      now: ctx.now,
      episodeKey,
      kind: 'PRE_WORKOUT',
      slot: 'preworkout',
      workoutId: workout.id,
      message: langOf(user.language) === 'he' ? 'אימון בקרוב. תאכל משהו קודם.' : 'Training soon. Eat something first.',
      category: 'CHECK_IN',
      rx: refuelPrescription(ctx.solverFoods, excludedTokens),
      foodIdBySlug: ctx.foodIdBySlug,
      summary: ctx.summary,
    });
    return true;
  }

  return false;
}

function formatClock(minute: number): string {
  const h = Math.floor(minute / 60);
  const m = minute % 60;
  const h12 = h % 12 || 12;
  const pad = String(m).padStart(2, '0');
  const suffix = h >= 12 ? 'pm' : 'am';
  return m === 0 ? `${h12} ${suffix}` : `${h12}:${pad} ${suffix}`;
}

async function createTrainingCheckIn(
  deps: ScoreConfidenceDeps,
  user: UserWithRelations,
  input: {
    now: Date;
    episodeKey: string;
    kind: string;
    slot: string;
    workoutId: string;
    message: string;
    category: 'CHECK_IN' | 'HEADS_UP' | 'REFUEL';
    rx: PrescriptionResult | null;
    foodIdBySlug: Map<string, string>;
    summary: ScoreConfidenceSummary;
  },
): Promise<void> {
  const { prisma } = deps;
  const checkIn = await prisma.checkIn.create({
    data: {
      userId: user.id,
      tier: 1,
      status: 'PENDING',
      deliveryStatus: 'CREATED',
      message: input.message,
      slot: input.slot,
      episodeKey: input.episodeKey,
      kind: input.kind,
      workoutId: input.workoutId,
    },
  });
  // No food fits the user's restrictions → the nudge still goes out, without a suggestion.
  const rx = input.rx;
  const created = rx
    ? await prisma.prescription.create({
        data: {
          userId: user.id,
          checkInId: checkIn.id,
          targetKcal: rx.targetKcal,
          targetProteinG: rx.targetProteinG,
          totalKcal: rx.totalKcal,
          totalProteinG: rx.totalProteinG,
          totalCarbsG: rx.totalCarbsG,
          totalFatG: rx.totalFatG,
          status: 'OFFERED',
          items: {
            create: rx.items.map((i) => ({
              foodItemId: input.foodIdBySlug.get(i.slug) ?? null,
              name: i.name,
              quantity: i.quantity,
              unit: 'serving',
              kcal: i.kcal,
              proteinG: i.proteinG,
              carbsG: i.carbsG,
              fatG: i.fatG,
            })),
          },
        },
      })
    : null;
  if (created) input.summary.prescriptionsCreated += 1;
  await markDelivered(deps, user.id, checkIn.id, 1, input.message, created?.id ?? null, input.now, input.category);
  await prisma.escalationState.upsert({
    where: { userId: user.id },
    create: { userId: user.id, lastCheckInAt: input.now, currentTier: 1 },
    update: { lastCheckInAt: input.now },
  });
  input.summary.checkInsCreated += 1;
}

async function applyDecision(
  deps: ScoreConfidenceDeps,
  user: UserWithRelations,
  checkInId: string,
  message: string | null,
  decision: EscalationDecision,
  now: Date,
  summary: ScoreConfidenceSummary,
): Promise<boolean> {
  const { prisma } = deps;

  switch (decision.kind) {
    case 'wait':
      return true;

    case 'resolve':
      await prisma.checkIn.update({
        where: { id: checkInId },
        data: { status: 'EXPIRED', resolvedAt: now },
      });
      summary.checkInsResolved += 1;
      return false;

    case 'redeliver':
      await prisma.checkIn.update({
        where: { id: checkInId },
        data: { status: 'PENDING', tier: decision.tier, deferUntil: null },
      });
      const rx = await prisma.prescription.findFirst({ where: { checkInId }, select: { id: true } });
      await markDelivered(deps, user.id, checkInId, decision.tier, message ?? 'Time to eat.', rx?.id ?? null, now);
      summary.checkInsRedelivered += 1;
      return true;

    case 'miss': {
      await prisma.checkIn.update({
        where: { id: checkInId },
        data: { status: 'ESCALATED', resolvedAt: now },
      });
      summary.misses += 1;

      await prisma.escalationState.upsert({
        where: { userId: user.id },
        create: {
          userId: user.id,
          consecutiveMisses: decision.consecutiveMisses,
          currentTier: decision.nextCurrentTier,
          backedOffUntil: decision.backedOffUntil,
        },
        update: {
          consecutiveMisses: decision.consecutiveMisses,
          currentTier: decision.nextCurrentTier,
          backedOffUntil: decision.backedOffUntil,
        },
      });

      if (decision.startTier3) {
        const opener = fallbackTierThree.opener({
          goal: (user.onboarding?.goal as Goal) ?? 'MAINTAIN',
          recentMisses: 3,
        });
        const conversationCheckIn = await prisma.checkIn.create({
          data: {
            userId: user.id,
            tier: 3,
            status: 'PENDING',
            deliveryStatus: 'CREATED',
            message: opener,
          },
        });
        await prisma.escalationConversation.create({
          data: { userId: user.id, checkInId: conversationCheckIn.id },
        });
        await markDelivered(deps, user.id, conversationCheckIn.id, 3, opener, null, now);
        summary.tier3Started += 1;
        return true;
      }
      return false;
    }

    default: {
      const _exhaustive: never = decision;
      return _exhaustive;
    }
  }
}

/** Only consulted while the modifier is switched on — Basic scoring needs no signals. */
async function wearableHaltedByStopConditions(prisma: PrismaClient, now: Date): Promise<boolean> {
  if (!wearableModifierKillSwitchOn()) return false;
  const evaluation = evaluateStopConditions(await gatherStopSignals(prisma, now), now);
  if (evaluation.haltWearable) {
    console.warn('scoreConfidence: wearable modifier halted by stop conditions', evaluation.reasons);
    captureError(new Error('wearable modifier halted by stop conditions'), {
      tags: { job: 'score', stop: evaluation.reasons.join(',') },
    });
  }
  return evaluation.haltWearable;
}

async function markDelivered(
  deps: ScoreConfidenceDeps,
  userId: string,
  checkInId: string,
  tier: number,
  body: string,
  prescriptionId: string | null,
  now: Date,
  category: 'CHECK_IN' | 'HEADS_UP' | 'REFUEL' = 'CHECK_IN',
): Promise<void> {
  const outcome = await deliverCheckIn({
    prisma: deps.prisma,
    push: deps.push,
    userId,
    payload: { userId, checkInId, tier, title: 'SetPoint', body, prescriptionId, category },
  });
  await deps.prisma.checkIn.update({
    where: { id: checkInId },
    data: {
      deliveryStatus: outcome.status,
      deliveredAt: outcome.status === 'SENT' ? now : null,
      lastPushError: outcome.lastPushError,
    },
  });
}
