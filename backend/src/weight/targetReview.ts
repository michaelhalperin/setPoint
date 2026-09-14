import type { PrismaClient } from '@prisma/client';
import type { Goal } from '../engine/types.js';
import { ADAPT_CONFIG, suggestTargetAdaptation, type AdaptSuggestion } from './adapt.js';

/** Nothing to review right now (not enough data, cooling down, or quiet mode). */
export class NoTargetReviewError extends Error {}
/** The target or suggestion moved since the client loaded it — refresh and retry. */
export class StaleTargetReviewError extends Error {}

/**
 * The calorie review the user can act on now, computed on the server from
 * their own weigh-ins. Clients never supply the numbers.
 */
export async function currentTargetSuggestion(
  prisma: PrismaClient,
  userId: string,
  now = new Date(),
): Promise<AdaptSuggestion | null> {
  const since = new Date(now.getTime() - ADAPT_CONFIG.windowDays * 86_400_000);
  const [user, lastDecision] = await Promise.all([
    prisma.user.findUnique({
      where: { id: userId },
      include: {
        onboarding: true,
        safetyScreening: true,
        weightEntries: { where: { measuredAt: { gte: since } }, orderBy: { measuredAt: 'desc' } },
      },
    }),
    prisma.weightTargetReview.findFirst({
      where: { userId, decidedAt: { not: null } },
      orderBy: { decidedAt: 'desc' },
    }),
  ]);
  const profile = user?.onboarding;
  if (!profile) return null;
  // Quiet mode (eating-concern screen or medical care): targets are the care
  // team's call, so the app never proposes changing them.
  if (!user.safetyScreening?.enforcementEnabled) return null;

  return suggestTargetAdaptation({
    goal: profile.goal as Goal,
    currentKcal: profile.dailyKcalTarget,
    paceKgPerWeek: profile.paceKgPerWeek,
    samples: user.weightEntries,
    lastDecisionAt: lastDecision?.decidedAt ?? null,
    now,
  });
}

/**
 * Applies the server's current suggestion. `expectedProposedKcal` is what the
 * user saw; if the suggestion has moved, nothing changes.
 */
export async function acceptTargetReview(
  prisma: PrismaClient,
  userId: string,
  expectedProposedKcal: number,
  now = new Date(),
): Promise<{ dailyKcalTarget: number }> {
  const suggestion = await currentTargetSuggestion(prisma, userId, now);
  if (!suggestion) throw new NoTargetReviewError('no target change to review');
  if (suggestion.proposedKcal !== expectedProposedKcal) {
    throw new StaleTargetReviewError('the suggested target changed — refresh');
  }

  await prisma.$transaction(async (tx) => {
    // Only move a target that is still the one the suggestion was based on.
    const moved = await tx.onboardingProfile.updateMany({
      where: { userId, dailyKcalTarget: suggestion.previousKcal },
      data: { dailyKcalTarget: suggestion.proposedKcal },
    });
    if (moved.count !== 1) throw new StaleTargetReviewError('the target changed — refresh');
    await tx.weightTargetReview.create({ data: reviewRow(userId, suggestion, 'ACCEPTED', now) });
  });
  return { dailyKcalTarget: suggestion.proposedKcal };
}

/** "Not now": records the decision so the weekly cooldown starts. */
export async function dismissTargetReview(
  prisma: PrismaClient,
  userId: string,
  now = new Date(),
): Promise<void> {
  const suggestion = await currentTargetSuggestion(prisma, userId, now);
  if (!suggestion) return;
  await prisma.weightTargetReview.create({ data: reviewRow(userId, suggestion, 'REJECTED', now) });
}

/** Restores the target from before the last accepted review, if nothing has changed it since. */
export async function undoLastTargetReview(
  prisma: PrismaClient,
  userId: string,
  now = new Date(),
): Promise<{ dailyKcalTarget: number }> {
  const last = await prisma.weightTargetReview.findFirst({
    where: { userId, status: 'ACCEPTED' },
    orderBy: { decidedAt: 'desc' },
  });
  if (!last) throw new NoTargetReviewError('no accepted target change to undo');

  await prisma.$transaction(async (tx) => {
    const restored = await tx.onboardingProfile.updateMany({
      where: { userId, dailyKcalTarget: last.proposedKcal },
      data: { dailyKcalTarget: last.previousKcal },
    });
    if (restored.count !== 1) throw new StaleTargetReviewError('the target changed since — edit it in Goal');
    await tx.weightTargetReview.update({
      where: { id: last.id },
      data: { status: 'UNDONE', decidedAt: now },
    });
  });
  return { dailyKcalTarget: last.previousKcal };
}

function reviewRow(
  userId: string,
  s: AdaptSuggestion,
  status: 'ACCEPTED' | 'REJECTED',
  now: Date,
) {
  return {
    userId,
    status,
    formulaVersion: s.formulaVersion,
    previousKcal: s.previousKcal,
    proposedKcal: s.proposedKcal,
    reason: s.reason,
    windowStart: s.windowStart,
    windowEnd: s.windowEnd,
    weighInCount: s.weighInCount,
    trendKgPerWeek: s.trendKgPerWeek,
    decidedAt: now,
  };
}
