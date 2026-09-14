import type { Prisma, PrismaClient } from '@prisma/client';
import {
  checkEligibility,
  checkInSlotAt,
  decideEscalation,
  deriveHoursSinceMeal,
  dueCheckIn,
  freshCheckInTier,
  isBiosignalFresh,
  msSinceLocalMidnight,
  startOfLocalDay,
  TIER,
  type EscalationDecision,
  type Goal,
  type SlotName,
} from '../engine/index.js';
import type { ManagerVoice } from '../managerVoice/types.js';
import { captureError } from '../observability/sentry.js';
import type { PushSender } from '../push/types.js';
import {
  computePrescriptionTarget,
  prescribe,
  prescriptionSummary,
  type SolverFood,
} from '../solver/index.js';

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
};

/**
 * The server-driven confidence job (plan §2). Runs on Vercel Cron via
 * `POST /api/cron/score`. Per onboarded user:
 *   1. advance any open check-in through the defer/escalation state machine,
 *   2. if nothing is pending and the user is eligible, check the meal schedule,
 *   3. when a meal is overdue, create a check-in + a solver prescription and deliver.
 *
 * Timing and prescription selection are deterministic — no model calls (§7).
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
  };

  const users = await deps.prisma.user.findMany({
    where: { onboarding: { isNot: null } },
    include: USER_INCLUDE,
  });
  summary.usersEvaluated = users.length;

  for (const user of users) {
    try {
      await processUser(deps, context, user, now, summary);
    } catch (err) {
      summary.errors += 1;
      console.error(`scoreConfidence: user ${user.id} failed`, err);
      captureError(err, { userId: user.id, tags: { job: 'score' } });
    }
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

  const [activeCheckIns, lastMeal, todayMeals, todayCheckIns, restrictions] = await Promise.all([
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
      select: { createdAt: true, tier: true },
    }),
    prisma.dietaryRestriction.findMany({ where: { userId: user.id, isHardExclusion: true } }),
  ]);

  const consumedKcal = todayMeals.reduce((acc, m) => acc + m.kcal, 0);
  const underTarget = consumedKcal < profile.dailyKcalTarget;

  // 1. Advance any open check-in.
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
      },
      state: escStateOf(user),
      // Logging a meal resolves the check-in outright, so an open one after a
      // snooze is still due unless the day's target has been met since.
      stillDue: isDeferred ? underTarget : null,
      now,
    });

    blocked =
      (await applyDecision(deps, user, ci.id, ci.message, decision, now, summary)) || blocked;
  }

  if (blocked || activeCheckIns.length > 0) {
    bump(summary, 'active_checkin');
    return;
  }

  // 2. Eligibility gate — checked before anything is evaluated (§2).
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

  // 3. Is a meal overdue? Usual meal time + grace, nothing logged, under target.
  const due = dueCheckIn({
    nowMin: localMinute(now, user.timezone),
    times: profile,
    mealMinutesToday: todayMeals.map((m) => localMinute(m.loggedAt, user.timezone)),
    checkedSlotsToday: todayCheckIns
      .filter((c) => c.tier < TIER.CONVERSATION)
      .map((c) => checkInSlotAt(localMinute(c.createdAt, user.timezone), profile))
      .filter((slot): slot is SlotName => slot !== null),
    consumedKcal,
    targetKcal: profile.dailyKcalTarget,
  });
  summary.scored += 1;
  if (!due) {
    bump(summary, 'not_due');
    return;
  }

  const hoursSinceMeal = deriveHoursSinceMeal(lastMeal?.loggedAt ?? null, user.createdAt, now);
  const biosignal =
    profile.mode === 'SMART' && user.biosignalState && isBiosignalFresh(user.biosignalState.updatedAt, now)
      ? user.biosignalState.hrvDeviation
      : null;
  // Audit row for the fired check-in (beta metrics read it).
  const score = await prisma.confidenceScore.create({
    data: {
      userId: user.id,
      computedAt: now,
      mode: profile.mode,
      score: 1,
      biosignalDeviation: biosignal,
      hoursSinceMeal,
      expectedGapHours: null,
      loggingSilence: null,
      threshold: 1,
      firedCheckIn: true,
    },
  });

  // 4. Solve for a directive prescription (§2, §5.4).
  const tier = freshCheckInTier(escStateOf(user));
  const target = computePrescriptionTarget({
    dailyKcalTarget: profile.dailyKcalTarget,
    consumedKcal,
    dailyProteinTargetG: profile.dailyProteinTargetG,
    consumedProteinG: todayMeals.reduce((acc, m) => acc + m.proteinG, 0),
  });

  const rx =
    ctx.solverFoods.length > 0
      ? prescribe(ctx.solverFoods, {
          targetKcal: target.targetKcal,
          targetProteinG: target.targetProteinG,
          excludedTokens: restrictions.map((r) => r.token),
          preferLowFriction: tier >= 2,
        })
      : null;
  const summaryLine = rx ? prescriptionSummary(rx) : null;

  // 5. Fire the check-in.
  const message = await deps.voice.checkInMessage({
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
      message,
      deliveredAt: now,
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

  await sendPush(deps, user.id, checkIn.id, tier, message, prescriptionId);
  await prisma.escalationState.upsert({
    where: { userId: user.id },
    create: { userId: user.id, lastCheckInAt: now, currentTier: tier },
    update: { lastCheckInAt: now },
  });
  summary.checkInsCreated += 1;
}

/** Applies an escalation decision. Returns whether a check-in still blocks new scoring. */
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
        data: { status: 'PENDING', tier: decision.tier, deferUntil: null, deliveredAt: now },
      });
      const rx = await prisma.prescription.findFirst({ where: { checkInId }, select: { id: true } });
      await sendPush(deps, user.id, checkInId, decision.tier, message ?? 'Time to eat.', rx?.id ?? null);
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
        const conversationCheckIn = await prisma.checkIn.create({
          data: { userId: user.id, tier: 3, status: 'PENDING', deliveredAt: now },
        });
        await prisma.escalationConversation.create({
          data: { userId: user.id, checkInId: conversationCheckIn.id },
        });
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

async function sendPush(
  deps: ScoreConfidenceDeps,
  userId: string,
  checkInId: string,
  tier: number,
  body: string,
  prescriptionId: string | null = null,
): Promise<void> {
  const tokens = await deps.prisma.pushToken.findMany({
    where: { userId, kind: 'alert' },
  });
  await deps.push.send(
    tokens.map((t) => t.token),
    { userId, checkInId, tier, title: 'SetPoint', body, prescriptionId },
  );
}
