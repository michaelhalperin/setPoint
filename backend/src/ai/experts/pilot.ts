import type { PrismaClient } from '@prisma/client';
import { flagOn } from '../../flags/index.js';

/**
 * Pre-registered pilot rules. Hard auto-kill is safety-only.
 * Metric deltas pause-and-inspect after a minimum sample — they do not auto-kill.
 */
export const PILOT = {
  hardKill: {
    layer1LlmTurn: true,
    uncaughtReviewMiss: true,
    safetyTripRateKill: 0.15,
    safetyTripRatePause: 0.05,
  },
  pauseAndInspect: {
    minUsersPerArm: 15,
    minCheckInsPerArm: 50,
  },
  expand: {
    keepBelowOpenerConfirm: 0.15,
    expandAtOpenerConfirm: 0.3,
  },
  contamination:
    'Holdout from the same trainer pool is leaky — athletes talk. ITT is primary; opener rates are secondary.',
} as const;

export type PilotCounts = {
  flagOnUsers: number;
  holdoutUsers: number;
  checkInsFlagOn: number;
  checkInsHoldout: number;
  opens: number;
  sends: number;
  confirms: number;
  trips: number;
  layer1LlmTurns: number;
};

export type PilotScore = {
  ittConfirmRate: number;
  openerRate: number;
  confirmAmongOpeners: number;
  tripRateOfTurns: number;
  sampleFloorMet: boolean;
  hardKill: string[];
  pauseTripRate: boolean;
  verdict: 'too_early' | 'keep' | 'expand' | 'inspect' | 'killed';
};

export function scorePilot(c: PilotCounts): PilotScore {
  const tripRateOfTurns = c.trips / Math.max(c.sends, 1);
  const openerRate = c.opens / Math.max(c.flagOnUsers, 1);
  const confirmAmongOpeners = c.confirms / Math.max(c.opens, 1);
  const ittConfirmRate = c.confirms / Math.max(c.flagOnUsers, 1);
  const sampleFloorMet =
    c.flagOnUsers >= PILOT.pauseAndInspect.minUsersPerArm &&
    c.holdoutUsers >= PILOT.pauseAndInspect.minUsersPerArm &&
    c.checkInsFlagOn >= PILOT.pauseAndInspect.minCheckInsPerArm &&
    c.checkInsHoldout >= PILOT.pauseAndInspect.minCheckInsPerArm;

  const hardKill: string[] = [];
  if (c.layer1LlmTurns > 0) hardKill.push('layer1_llm_turn');
  if (tripRateOfTurns > PILOT.hardKill.safetyTripRateKill) hardKill.push('trip_rate_kill');

  const pauseTripRate = tripRateOfTurns > PILOT.hardKill.safetyTripRatePause;
  let verdict: PilotScore['verdict'] = 'too_early';
  if (hardKill.length) verdict = 'killed';
  else if (!sampleFloorMet) verdict = 'too_early';
  else if (pauseTripRate) verdict = 'inspect';
  else if (confirmAmongOpeners >= PILOT.expand.expandAtOpenerConfirm) verdict = 'expand';
  else if (confirmAmongOpeners < PILOT.expand.keepBelowOpenerConfirm) verdict = 'keep';
  else verdict = 'inspect';

  return {
    ittConfirmRate,
    openerRate,
    confirmAmongOpeners,
    tripRateOfTurns,
    sampleFloorMet,
    hardKill,
    pauseTripRate,
    verdict,
  };
}

export async function gatherPilot(prisma: PrismaClient) {
  const [users, flagRow, events, trips] = await Promise.all([
    prisma.user.findMany({
      where: { role: 'USER' },
      select: { id: true, role: true, group: true },
    }),
    prisma.featureFlag.findUnique({ where: { key: 'nutrition_chat' } }),
    prisma.analyticsEvent.findMany({
      where: { name: { in: ['expert_open', 'expert_send', 'expert_confirm'] } },
      select: { userId: true, name: true },
      take: 50_000,
    }),
    prisma.expertSafetyTrip.count(),
  ]);

  const flagOnIds = new Set(users.filter((u) => flagOn('nutrition_chat', u, flagRow ?? undefined)).map((u) => u.id));
  const poolGroups = new Set(flagRow?.groups ?? users.map((u) => u.group).filter((c): c is string => !!c));
  const holdoutIds = new Set(
    users
      .filter((u) => !flagOnIds.has(u.id) && u.group !== null && poolGroups.has(u.group))
      .map((u) => u.id),
  );

  const since = new Date(Date.now() - 28 * 86_400_000);
  const [checkInsFlagOn, checkInsHoldout] = await Promise.all([
    flagOnIds.size
      ? prisma.checkIn.count({ where: { userId: { in: [...flagOnIds] }, createdAt: { gte: since } } })
      : 0,
    holdoutIds.size
      ? prisma.checkIn.count({ where: { userId: { in: [...holdoutIds] }, createdAt: { gte: since } } })
      : 0,
  ]);

  const openers = new Set<string>();
  let sends = 0;
  let confirms = 0;
  for (const e of events) {
    if (e.name === 'expert_open' && e.userId) openers.add(e.userId);
    if (e.name === 'expert_send') sends += 1;
    if (e.name === 'expert_confirm') confirms += 1;
  }

  const counts: PilotCounts = {
    flagOnUsers: flagOnIds.size,
    holdoutUsers: holdoutIds.size,
    checkInsFlagOn,
    checkInsHoldout,
    opens: openers.size,
    sends,
    confirms,
    trips,
    layer1LlmTurns: 0,
  };
  const score = scorePilot(counts);
  return {
    ...counts,
    ...score,
    contamination: PILOT.contamination,
    rules: PILOT,
  };
}
