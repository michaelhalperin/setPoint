import type { Prisma, PrismaClient } from '@prisma/client';
import { fallbackTierThree } from '../ai/tierThree.js';
import { env } from '../env.js';
import {
  checkEligibility,
  checkInSlotAt,
  computeBehaviorScore,
  SCORE_CONFIG,
  decideEscalation,
  deriveHoursSinceMeal,
  dueCheckIn,
  expectedGapHours,
  freshCheckInTier,
  isBiosignalFresh,
  localDateISO,
  localWeekday,
  mealTimesOn,
  msSinceLocalMidnight,
  startOfLocalDay,
  TIER,
  userInWearableCohort,
  wearableModifierKillSwitchOn,
  type EscalationDecision,
  type Goal,
  type SlotName,
} from '../engine/index.js';
import { evaluateStopConditions } from '../engine/stopConditions.js';
import { fallbackManagerVoice } from '../managerVoice/fallback.js';
import { gatherStopSignals } from '../metrics/stopSignals.js';
import type { ManagerVoice, ManagerVoiceContext } from '../managerVoice/types.js';
import { captureError } from '../observability/sentry.js';
import { deliverCheckIn } from '../push/deliver.js';
import type { PushSender } from '../push/types.js';
import {
  computePrescriptionTarget,
  prescribe,
  prescriptionSummary,
  type SolverFood,
} from '../solver/index.js';
import { prescriptionFromSavedMeal } from '../savedMeals/index.js';

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
  };

  const foodRows = await deps.prisma.foodItem.findMany({ where: { isStaple: true } });
  const context: JobContext = {
    solverFoods: foodRows.map((f) => ({
      slug: f.slug,
      name: f.name,
      servingDesc: f.servingDesc,
      kcal: f.kcal,
      proteinG: f.proteinG,
      carbsG: f.carbsG,
      fatG: f.fatG,
      tags: f.tags,
      allergens: f.allergens,
    })),
    foodIdBySlug: new Map(foodRows.map((f) => [f.slug, f.id])),
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

  const { prisma } = deps;
  const dayStart = startOfLocalDay(now, user.timezone);

  const [activeCheckIns, lastMeal, todayMeals, todayCheckIns, restrictions, usualForSlot] = await Promise.all([
    prisma.checkIn.findMany({
      where: { userId: user.id, status: { in: ['PENDING', 'DEFERRED'] } },
      orderBy: { createdAt: 'desc' },
    }),
    prisma.meal.findFirst({ where: { userId: user.id }, orderBy: { loggedAt: 'desc' } }),
    prisma.meal.findMany({
      where: { userId: user.id, loggedAt: { gte: dayStart } },
      select: { kcal: true, proteinG: true, loggedAt: true },
    }),
    prisma.checkIn.findMany({
      where: { userId: user.id, createdAt: { gte: dayStart } },
      select: { createdAt: true, tier: true, episodeKey: true },
    }),
    prisma.dietaryRestriction.findMany({ where: { userId: user.id, isHardExclusion: true } }),
    prisma.savedMeal.findMany({
      where: { userId: user.id, useInCheckIns: true },
      orderBy: [{ lastUsedAt: 'desc' }, { useCount: 'desc' }],
    }),
  ]);

  const consumedKcal = todayMeals.reduce((acc, m) => acc + m.kcal, 0);
  const underTarget = consumedKcal < profile.dailyKcalTarget;

  let blocked = false;
  for (const ci of activeCheckIns) {
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
    blocked = (await applyDecision(deps, user, ci.id, ci.message, decision, now, summary)) || blocked;
  }

  if (blocked || activeCheckIns.length > 0) {
    bump(summary, 'active_checkin');
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
    return;
  }

  const times = mealTimesOn(profile, localWeekday(now, user.timezone));
  const due = dueCheckIn({
    nowMin: localMinute(now, user.timezone),
    times,
    mealMinutesToday: todayMeals.map((m) => localMinute(m.loggedAt, user.timezone)),
    checkedSlotsToday: todayCheckIns
      .filter((c) => c.tier < TIER.CONVERSATION)
      .map((c) => checkInSlotAt(localMinute(c.createdAt, user.timezone), times))
      .filter((slot): slot is SlotName => slot !== null),
    consumedKcal,
    targetKcal: profile.dailyKcalTarget,
  });
  summary.scored += 1;
  if (!due) {
    bump(summary, 'not_due');
    return;
  }

  const episodeKey = `${localDateISO(now, user.timezone)}:${due.slot}`;
  const existing = todayCheckIns.find((c) => c.episodeKey === episodeKey);
  if (existing) {
    bump(summary, 'duplicate_episode');
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
    targetKcal: profile.dailyKcalTarget,
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
    return;
  }

  const excludedTokens = [...restrictions.map((r) => r.token), ...(profile.dislikedFoods ?? [])];
  const pantry = profile.pantryTokens ?? [];

  const tier = freshCheckInTier(escStateOf(user));
  const target = computePrescriptionTarget({
    dailyKcalTarget: profile.dailyKcalTarget,
    consumedKcal,
    dailyProteinTargetG: profile.dailyProteinTargetG,
    consumedProteinG: todayMeals.reduce((acc, m) => acc + m.proteinG, 0),
  });

  const usual = usualForSlot.find((m) => m.suggestSlot === due.slot) ?? null;
  const rx = usual
    ? prescriptionFromSavedMeal(usual, target)
    : ctx.solverFoods.length > 0
      ? prescribe(ctx.solverFoods, {
          targetKcal: target.targetKcal,
          targetProteinG: target.targetProteinG,
          excludedTokens,
          preferLowFriction: tier >= 2,
          pantryTokens: pantry,
          prepTimeMaxMin: profile.prepTimeMaxMin,
        })
      : null;
  const summaryLine = rx ? prescriptionSummary(rx) : null;

  const message = await checkInCopy(deps.voice, {
    tier,
    goal: profile.goal as Goal,
    hoursSinceMeal,
    kcalGap: target.targetKcal,
    prescriptionSummary: summaryLine,
    slot: due.slot,
  });

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

  await markDelivered(deps, user.id, checkIn.id, tier, message, prescriptionId, now);
  await prisma.escalationState.upsert({
    where: { userId: user.id },
    create: { userId: user.id, lastCheckInAt: now, currentTier: tier },
    update: { lastCheckInAt: now },
  });
  summary.checkInsCreated += 1;
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

/** How long a check-in waits for the manager's-voice line before sending the deterministic one. */
export const CHECK_IN_COPY_TIMEOUT_MS = 4_000;

async function checkInCopy(voice: ManagerVoice, ctx: ManagerVoiceContext): Promise<string> {
  const fallback = () => fallbackManagerVoice.checkInMessage(ctx);
  let timer: ReturnType<typeof setTimeout> | undefined;
  const timedOut = new Promise<null>((resolve) => {
    timer = setTimeout(() => resolve(null), CHECK_IN_COPY_TIMEOUT_MS);
  });
  try {
    const line = await Promise.race([voice.checkInMessage(ctx).catch(() => null), timedOut]);
    return line?.trim() ? line : await fallback();
  } finally {
    clearTimeout(timer);
  }
}

async function markDelivered(
  deps: ScoreConfidenceDeps,
  userId: string,
  checkInId: string,
  tier: number,
  body: string,
  prescriptionId: string | null,
  now: Date,
): Promise<void> {
  const outcome = await deliverCheckIn({
    prisma: deps.prisma,
    push: deps.push,
    userId,
    payload: { userId, checkInId, tier, title: 'SetPoint', body, prescriptionId },
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
