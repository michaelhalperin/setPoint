/**
 * Engine configuration. Check-in timing lives in mealSchedule.ts (usual meal
 * time + grace). These constants cover escalation, snooze, biosignal freshness
 * for the audit row, and the hours-since-meal fallback used when nothing has
 * been logged.
 */

export const ENGINE_CONFIG = {
  /** When the user has never logged a meal, hoursSinceMeal falls back to this
   *  (capped account age) so a brand-new account cannot look endlessly overdue. */
  noMealFallbackHours: 16,

  /** A BiosignalState older than this is ignored on the audit row. */
  biosignalMaxAgeHours: 6,

  /** Snooze length applied when the user defers a check-in. */
  snoozeHours: 2,

  /** An unanswered PENDING check-in older than this counts as a full miss. */
  checkInTtlHours: 4,

  /** Defers on a tier-2 check-in beyond this count end the episode as a miss. */
  maxDefersBeforeMiss: 2,

  /** Consecutive full misses that trigger the tier-3 conversation. */
  missesBeforeTier3: 3,

  /** After tier 3, the engine stops scoring this user for this long (§2: "back off"). */
  backoffHoursAfterTier3: 24,
} as const;

export type EngineConfig = typeof ENGINE_CONFIG;

/** The three escalation tiers (plan §2). Tier 3 is a conversation, not a notification. */
export const TIER = { GENTLE: 1, FIRM: 2, CONVERSATION: 3 } as const;
