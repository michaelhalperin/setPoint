import { ENGINE_CONFIG, type EngineConfig } from './config.js';
import { hoursBetween } from './types.js';

/**
 * Hours since the user's last logged meal. When they have never logged one,
 * falls back to their (capped) account age so a brand-new account cannot look
 * endlessly overdue on the audit row / check-in copy.
 */
export function deriveHoursSinceMeal(
  lastMealAt: Date | null,
  accountCreatedAt: Date,
  now: Date,
  config: EngineConfig = ENGINE_CONFIG,
): number {
  if (lastMealAt) return hoursBetween(lastMealAt, now);
  return Math.min(hoursBetween(accountCreatedAt, now), config.noMealFallbackHours);
}

/** Whether a BiosignalState is recent enough to record on the audit row. */
export function isBiosignalFresh(
  updatedAt: Date,
  now: Date,
  config: EngineConfig = ENGINE_CONFIG,
): boolean {
  return hoursBetween(updatedAt, now) <= config.biosignalMaxAgeHours;
}
