/**
 * Confidence engine configuration.
 *
 * The FORMULA is permanent (plan §2, §7): a deterministic weighted sum, never a
 * model call, always auditable. Only these WEIGHTS and the surrounding constants
 * are tunable — and only against real beta data (§8), never by model judgement.
 *
 *   Smart: 0.5·biosignal + 0.3·(hoursSinceMeal / expectedGap) + 0.2·loggingSilence
 *   Basic:               0.6·(hoursSinceMeal / expectedGap) + 0.4·loggingSilence
 *
 * A check-in fires when confidence strictly exceeds `confidenceThreshold`.
 */

export const CONFIDENCE_WEIGHTS = {
  smart: { biosignal: 0.5, mealGap: 0.3, silence: 0.2 },
  basic: { mealGap: 0.6, silence: 0.4 },
} as const;

export const ENGINE_CONFIG = {
  /** Check-in fires when confidence is strictly greater than this. */
  confidenceThreshold: 0.7,

  /** The meal-gap ratio (hoursSinceMeal / expectedGap) is clamped to this ceiling
   *  so a very overdue meal still carries more weight than an exactly-due one,
   *  without letting a single term dominate unboundedly. */
  mealGapRatioCeiling: 1.5,

  /** loggingSilence saturates to 1 after this many hours with nothing logged. */
  silenceHorizonHours: 8,

  /** When the user has never logged a meal, hoursSinceMeal falls back to this
   *  (capped account age) so a brand-new account cannot immediately fire. */
  noMealFallbackHours: 16,

  /** |z-score| of biosignal deviation at which the biosignal term saturates to 1. */
  biosignalZFullScale: 2,

  /** A BiosignalState older than this is ignored; Smart mode then scores as Basic. */
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
