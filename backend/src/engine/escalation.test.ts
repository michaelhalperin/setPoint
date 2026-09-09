import { describe, expect, it } from 'vitest';
import { ENGINE_CONFIG } from './config.js';
import {
  decideEscalation,
  freshCheckInTier,
  type ActiveCheckIn,
  type EscalationState,
} from './escalation.js';

const NOW = new Date('2026-04-01T12:00:00Z');
const hoursAgo = (h: number) => new Date(NOW.getTime() - h * 3_600_000);

const pending = (over: Partial<ActiveCheckIn> = {}): ActiveCheckIn => ({
  status: 'PENDING',
  tier: 1,
  deferCount: 0,
  deliveredAt: hoursAgo(1),
  deferUntil: null,
  ...over,
});

const deferred = (over: Partial<ActiveCheckIn> = {}): ActiveCheckIn => ({
  status: 'DEFERRED',
  tier: 1,
  deferCount: 1,
  deliveredAt: hoursAgo(3),
  deferUntil: hoursAgo(0.1),
  ...over,
});

const state = (over: Partial<EscalationState> = {}): EscalationState => ({
  consecutiveMisses: 0,
  currentTier: 1,
  ...over,
});

describe('decideEscalation', () => {
  it('waits while a PENDING check-in is still within its TTL', () => {
    expect(
      decideEscalation({ checkIn: pending({ deliveredAt: hoursAgo(1) }), state: state(), freshConfidence: null, now: NOW }),
    ).toEqual({ kind: 'wait' });
  });

  it('waits while a defer snooze is still running', () => {
    expect(
      decideEscalation({
        checkIn: deferred({ deferUntil: new Date(NOW.getTime() + 3_600_000) }),
        state: state(),
        freshConfidence: 0.9,
        now: NOW,
      }),
    ).toEqual({ kind: 'wait' });
  });

  it('records a miss when a PENDING check-in outlives its TTL unanswered', () => {
    const d = decideEscalation({
      checkIn: pending({ deliveredAt: hoursAgo(ENGINE_CONFIG.checkInTtlHours + 1) }),
      state: state({ consecutiveMisses: 0 }),
      freshConfidence: null,
      now: NOW,
    });
    expect(d).toMatchObject({ kind: 'miss', consecutiveMisses: 1, startTier3: false, backedOffUntil: null });
  });

  it('resolves without a miss when confidence has dropped by the re-check', () => {
    expect(
      decideEscalation({ checkIn: deferred(), state: state(), freshConfidence: 0.4, now: NOW }),
    ).toEqual({ kind: 'resolve' });
  });

  it('escalates a tier-1 episode to tier 2 when still overdue', () => {
    expect(
      decideEscalation({ checkIn: deferred({ tier: 1 }), state: state(), freshConfidence: 0.9, now: NOW }),
    ).toEqual({ kind: 'redeliver', tier: 2 });
  });

  it('gives a tier-2 episode one more nudge before calling it a miss', () => {
    expect(
      decideEscalation({
        checkIn: deferred({ tier: 2, deferCount: 1 }),
        state: state(),
        freshConfidence: 0.9,
        now: NOW,
      }),
    ).toEqual({ kind: 'redeliver', tier: 2 });
  });

  it('records a miss once a tier-2 episode is deferred too many times', () => {
    const d = decideEscalation({
      checkIn: deferred({ tier: 2, deferCount: ENGINE_CONFIG.maxDefersBeforeMiss }),
      state: state({ consecutiveMisses: 1 }),
      freshConfidence: 0.9,
      now: NOW,
    });
    expect(d).toMatchObject({ kind: 'miss', consecutiveMisses: 2, startTier3: false });
  });

  it('starts tier 3 and backs off on the third consecutive miss', () => {
    const d = decideEscalation({
      checkIn: pending({ deliveredAt: hoursAgo(ENGINE_CONFIG.checkInTtlHours + 1) }),
      state: state({ consecutiveMisses: ENGINE_CONFIG.missesBeforeTier3 - 1 }),
      freshConfidence: null,
      now: NOW,
    });
    expect(d.kind).toBe('miss');
    if (d.kind !== 'miss') return;
    expect(d.startTier3).toBe(true);
    expect(d.nextCurrentTier).toBe(3);
    expect(d.consecutiveMisses).toBe(0); // reset after tier 3 begins
    expect(d.backedOffUntil?.getTime()).toBe(NOW.getTime() + ENGINE_CONFIG.backoffHoursAfterTier3 * 3_600_000);
  });
});

describe('freshCheckInTier', () => {
  it('opens at the running tier, capped at firm', () => {
    expect(freshCheckInTier({ consecutiveMisses: 0, currentTier: 1 })).toBe(1);
    expect(freshCheckInTier({ consecutiveMisses: 1, currentTier: 2 })).toBe(2);
    expect(freshCheckInTier({ consecutiveMisses: 5, currentTier: 3 })).toBe(2);
  });
});
