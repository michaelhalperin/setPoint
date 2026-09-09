import type { Prisma, PrismaClient } from '@prisma/client';
import {
  checkEligibility,
  computeConfidence,
  decideEscalation,
  deriveHoursSinceLastLog,
  deriveHoursSinceMeal,
  expectedGapHours,
  freshCheckInTier,
  isBiosignalFresh,
  type ConfidenceInput,
  type EscalationDecision,
  type Goal,
  type Mode,
} from '../engine/index.js';
import type { ManagerVoice } from '../managerVoice/types.js';
import type { PushSender } from '../push/types.js';

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

/**
 * The server-driven confidence job (plan §2). Runs on Vercel Cron via
 * `POST /api/cron/score`. For each onboarded user it:
 *   1. advances any open check-in through the defer/escalation state machine,
 *   2. if nothing is pending and the user is eligible, scores confidence,
 *   3. fires a check-in when the score clears the threshold.
 *
 * All scoring is the deterministic engine — no model calls (§7).
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
    misses: 0,
    tier3Started: 0,
    errors: 0,
    skipped: {},
  };

  const users = await deps.prisma.user.findMany({
    where: { onboarding: { isNot: null } },
    include: USER_INCLUDE,
  });
  summary.usersEvaluated = users.length;

  for (const user of users) {
    try {
      await processUser(deps, user, now, summary);
    } catch (err) {
      summary.errors += 1;
      console.error(`scoreConfidence: user ${user.id} failed`, err);
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

function buildConfidenceInput(
  user: UserWithRelations,
  lastMealAt: Date | null,
  now: Date,
): ConfidenceInput {
  const profile = user.onboarding!;
  const mode = profile.mode as Mode;

  let biosignal: ConfidenceInput['biosignal'] = null;
  if (
    mode === 'SMART' &&
    user.biosignalState &&
    isBiosignalFresh(user.biosignalState.updatedAt, now)
  ) {
    biosignal = {
      hrvZ: user.biosignalState.hrvDeviation,
      rhrZ: user.biosignalState.rhrDeviation ?? null,
    };
  }

  return {
    mode,
    hoursSinceMeal: deriveHoursSinceMeal(lastMealAt, user.createdAt, now),
    expectedGapHours: expectedGapHours(profile),
    hoursSinceLastLog: deriveHoursSinceLastLog(lastMealAt, user.createdAt, now),
    biosignal,
  };
}

async function processUser(
  deps: ScoreConfidenceDeps,
  user: UserWithRelations,
  now: Date,
  summary: ScoreConfidenceSummary,
): Promise<void> {
  const profile = user.onboarding;
  if (!profile) return;

  const { prisma } = deps;

  const [activeCheckIns, lastMeal] = await Promise.all([
    prisma.checkIn.findMany({
      where: { userId: user.id, status: { in: ['PENDING', 'DEFERRED'] } },
      orderBy: { createdAt: 'desc' },
    }),
    prisma.meal.findFirst({ where: { userId: user.id }, orderBy: { loggedAt: 'desc' } }),
  ]);

  const input = buildConfidenceInput(user, lastMeal?.loggedAt ?? null, now);

  // 1. Advance any open check-in.
  let blocked = false;
  for (const ci of activeCheckIns) {
    const isDeferred = ci.status === 'DEFERRED';
    const freshConfidence = isDeferred ? computeConfidence(input).score : null;

    const decision = decideEscalation({
      checkIn: {
        status: isDeferred ? 'DEFERRED' : 'PENDING',
        tier: ci.tier,
        deferCount: ci.deferCount,
        deliveredAt: ci.deliveredAt ?? ci.createdAt,
        deferUntil: ci.deferUntil,
      },
      state: escStateOf(user),
      freshConfidence,
      now,
    });

    blocked = (await applyDecision(deps, user, ci.id, ci.tier, ci.message, decision, now, summary)) || blocked;
  }

  if (blocked || activeCheckIns.length > 0) {
    bump(summary, 'active_checkin');
    return;
  }

  // 2. Eligibility gate — checked before any scoring (§2).
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

  // 3. Score.
  const result = computeConfidence(input);
  const score = await prisma.confidenceScore.create({
    data: {
      userId: user.id,
      computedAt: now,
      mode: input.mode,
      score: result.score,
      biosignalDeviation: result.components.biosignalDeviation,
      hoursSinceMeal: input.hoursSinceMeal,
      expectedGapHours: input.expectedGapHours,
      loggingSilence: result.components.loggingSilence,
      threshold: result.threshold,
      firedCheckIn: result.fires,
    },
  });
  summary.scored += 1;

  if (!result.fires) return;

  // 4. Fire a check-in.
  const tier = freshCheckInTier(escStateOf(user));
  const message = await deps.voice.checkInMessage({
    tier,
    goal: profile.goal as Goal,
    hoursSinceMeal: input.hoursSinceMeal,
    kcalGap: null,
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

  await sendPush(deps, user.id, checkIn.id, tier, message);
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
  currentTier: number,
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

    case 'redeliver': {
      await prisma.checkIn.update({
        where: { id: checkInId },
        data: { status: 'PENDING', tier: decision.tier, deferUntil: null, deliveredAt: now },
      });
      await sendPush(deps, user.id, checkInId, decision.tier, message ?? 'Time to eat.');
      summary.checkInsRedelivered += 1;
      return true;
    }

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
): Promise<void> {
  const tokens = await deps.prisma.pushToken.findMany({ where: { userId } });
  await deps.push.send(
    tokens.map((t) => t.token),
    { userId, checkInId, tier, title: 'SetPoint', body },
  );
}
