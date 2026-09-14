import type { PrismaClient } from '@prisma/client';
import { STOP_CONFIG, type StopSignals } from '../engine/stopConditions.js';
import { userInWearableCohort } from '../engine/flags.js';

/** A check-in still CREATED this long after creation never made it out. */
const STUCK_CREATED_MIN = 10;

/** Reads the stop-condition signals for the last `STOP_CONFIG.windowDays`. */
export async function gatherStopSignals(prisma: PrismaClient, now = new Date()): Promise<StopSignals> {
  const since = new Date(now.getTime() - STOP_CONFIG.windowDays * 86_400_000);
  const stuckBefore = now.getTime() - STUCK_CREATED_MIN * 60_000;

  const [heartbeat, checkIns, smartUsers] = await Promise.all([
    prisma.schedulerHeartbeat.findUnique({ where: { job: 'score' } }),
    prisma.checkIn.findMany({
      where: { createdAt: { gte: since, lte: now }, tier: { lt: 3 } },
      select: {
        createdAt: true,
        deliveryStatus: true,
        feedbackPositive: true,
        confidenceScore: { select: { wearableUsed: true } },
      },
    }),
    prisma.user.findMany({
      where: { onboarding: { is: { mode: 'SMART' } } },
      select: { id: true, wearableModifierEnabled: true, escalationState: { select: { checkInsPaused: true } } },
    }),
  ]);

  const delivery = { numerator: 0, denominator: 0 };
  const negativeFeedback = { wearable: { numerator: 0, denominator: 0 }, control: { numerator: 0, denominator: 0 } };
  for (const c of checkIns) {
    const stillCreated = c.deliveryStatus === 'CREATED';
    if (!stillCreated || c.createdAt.getTime() < stuckBefore) {
      delivery.denominator += 1;
      if (c.deliveryStatus === 'FAILED' || stillCreated) delivery.numerator += 1;
    }
    const cohort = c.confidenceScore?.wearableUsed ? negativeFeedback.wearable : negativeFeedback.control;
    cohort.denominator += 1;
    if (c.feedbackPositive === false) cohort.numerator += 1;
  }

  const paused = { wearable: { numerator: 0, denominator: 0 }, control: { numerator: 0, denominator: 0 } };
  for (const u of smartUsers) {
    const cohort = userInWearableCohort(u.id, u.wearableModifierEnabled) ? paused.wearable : paused.control;
    cohort.denominator += 1;
    if (u.escalationState?.checkInsPaused) cohort.numerator += 1;
  }

  return {
    schedulerLastRunAt: heartbeat?.lastRunAt ?? null,
    schedulerLastOk: heartbeat?.lastOk ?? null,
    delivery,
    negativeFeedback,
    paused,
  };
}
