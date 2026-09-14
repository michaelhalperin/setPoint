import type { PrismaClient } from '@prisma/client';
import { describe, expect, it } from 'vitest';
import { gatherStopSignals } from './stopSignals.js';

const NOW = new Date('2026-09-14T12:00:00Z');
const minutesAgo = (m: number) => new Date(NOW.getTime() - m * 60_000);

function fake(checkIns: Record<string, unknown>[]) {
  return {
    schedulerHeartbeat: { findUnique: async () => ({ lastRunAt: minutesAgo(12), lastOk: true }) },
    checkIn: { findMany: async () => checkIns },
    user: { findMany: async () => [] },
  } as unknown as PrismaClient;
}

describe('gatherStopSignals', () => {
  it('counts failed and never-sent check-ins, but not ones still being sent', async () => {
    const s = await gatherStopSignals(
      fake([
        { createdAt: minutesAgo(60), deliveryStatus: 'SENT', feedbackPositive: null, confidenceScore: null },
        { createdAt: minutesAgo(60), deliveryStatus: 'FAILED', feedbackPositive: null, confidenceScore: null },
        { createdAt: minutesAgo(60), deliveryStatus: 'CREATED', feedbackPositive: null, confidenceScore: null },
        { createdAt: minutesAgo(2), deliveryStatus: 'CREATED', feedbackPositive: null, confidenceScore: null },
      ]),
      NOW,
    );
    expect(s.delivery).toEqual({ numerator: 2, denominator: 3 });
    expect(s.schedulerLastOk).toBe(true);
  });

  it('splits negative feedback by whether the wearable shaped the check-in', async () => {
    const s = await gatherStopSignals(
      fake([
        { createdAt: minutesAgo(60), deliveryStatus: 'SENT', feedbackPositive: false, confidenceScore: { wearableUsed: true } },
        { createdAt: minutesAgo(60), deliveryStatus: 'SENT', feedbackPositive: true, confidenceScore: { wearableUsed: true } },
        { createdAt: minutesAgo(60), deliveryStatus: 'SENT', feedbackPositive: false, confidenceScore: { wearableUsed: false } },
      ]),
      NOW,
    );
    expect(s.negativeFeedback.wearable).toEqual({ numerator: 1, denominator: 2 });
    expect(s.negativeFeedback.control).toEqual({ numerator: 1, denominator: 1 });
  });
});
