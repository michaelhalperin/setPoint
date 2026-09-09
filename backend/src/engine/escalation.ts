import { ENGINE_CONFIG, TIER, type EngineConfig } from './config.js';
import { MS_PER_HOUR } from './types.js';

export type ActiveCheckIn = {
  status: 'PENDING' | 'DEFERRED';
  tier: number;
  deferCount: number;
  /** When the current tier's notification was delivered (drives the PENDING TTL). */
  deliveredAt: Date;
  deferUntil: Date | null;
};

export type EscalationState = {
  consecutiveMisses: number;
  currentTier: number;
};

export type EscalationInput = {
  checkIn: ActiveCheckIn;
  state: EscalationState;
  /** Fresh confidence at re-check time. Null for an unanswered-TTL expiry (no re-score). */
  freshConfidence: number | null;
  now: Date;
  config?: EngineConfig;
};

export type EscalationDecision =
  /** Nothing to do yet — snooze still running, or PENDING within its TTL. */
  | { kind: 'wait' }
  /** Close the episode with no miss recorded (confidence has dropped). */
  | { kind: 'resolve' }
  /** Re-notify the user at this tier (bumps a tier-1 episode to tier 2). */
  | { kind: 'redeliver'; tier: number }
  /** The episode is a full miss. */
  | {
      kind: 'miss';
      consecutiveMisses: number;
      /** Reset the running tier to this after the miss. */
      nextCurrentTier: number;
      /** Start the tier-3 conversation now. */
      startTier3: boolean;
      /** Set when tier 3 starts — the engine backs off until then (§2). */
      backedOffUntil: Date | null;
    };

/**
 * The defer / escalation state machine (plan §2). Pure. The job layer applies
 * the returned decision to the database.
 */
export function decideEscalation(input: EscalationInput): EscalationDecision {
  const config = input.config ?? ENGINE_CONFIG;
  const { checkIn, state, freshConfidence, now } = input;

  // Deferred, but the snooze window is still open.
  if (checkIn.status === 'DEFERRED' && checkIn.deferUntil && checkIn.deferUntil > now) {
    return { kind: 'wait' };
  }

  // Delivered but untouched: wait until the TTL, then it's a full miss.
  if (checkIn.status === 'PENDING') {
    const ageHours = (now.getTime() - checkIn.deliveredAt.getTime()) / MS_PER_HOUR;
    if (ageHours < config.checkInTtlHours) return { kind: 'wait' };
    return registerMiss(state, now, config);
  }

  // Deferred and the snooze has elapsed → re-check confidence.
  if (freshConfidence !== null && freshConfidence <= config.confidenceThreshold) {
    // No longer overdue (likely ate without logging). Benefit of the doubt (§8).
    return { kind: 'resolve' };
  }

  // Still overdue after deferring.
  if (checkIn.tier < TIER.FIRM) return { kind: 'redeliver', tier: TIER.FIRM };
  if (checkIn.deferCount < config.maxDefersBeforeMiss) return { kind: 'redeliver', tier: TIER.FIRM };
  return registerMiss(state, now, config);
}

function registerMiss(
  state: EscalationState,
  now: Date,
  config: EngineConfig,
): Extract<EscalationDecision, { kind: 'miss' }> {
  const consecutiveMisses = state.consecutiveMisses + 1;
  const startTier3 = consecutiveMisses >= config.missesBeforeTier3;

  return {
    kind: 'miss',
    consecutiveMisses: startTier3 ? 0 : consecutiveMisses,
    nextCurrentTier: startTier3
      ? TIER.CONVERSATION
      : Math.min(TIER.FIRM, state.currentTier + 1),
    startTier3,
    backedOffUntil: startTier3
      ? new Date(now.getTime() + config.backoffHoursAfterTier3 * MS_PER_HOUR)
      : null,
  };
}

/** Tier for a fresh check-in, given the user's running escalation tier. */
export function freshCheckInTier(state: EscalationState): number {
  return Math.min(Math.max(state.currentTier, TIER.GENTLE), TIER.FIRM);
}
