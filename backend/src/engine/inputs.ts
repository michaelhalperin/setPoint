import { ENGINE_CONFIG, type EngineConfig } from './config.js';
import { hoursBetween } from './types.js';

/**
 * Hours since the user's last logged meal. When they have never logged one,
 * falls back to their (capped) account age so a brand-new account cannot
 * immediately trip a check-in.
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

/**
 * Hours since the user last logged anything. v1 treats "a log" as a meal entry;
 * when more interaction signals exist, pass the most recent of them here.
 */
export function deriveHoursSinceLastLog(
  lastLogAt: Date | null,
  accountCreatedAt: Date,
  now: Date,
): number {
  return hoursBetween(lastLogAt ?? accountCreatedAt, now);
}

/** Whether a BiosignalState is recent enough to feed Smart-mode scoring. */
export function isBiosignalFresh(
  updatedAt: Date,
  now: Date,
  config: EngineConfig = ENGINE_CONFIG,
): boolean {
  return hoursBetween(updatedAt, now) <= config.biosignalMaxAgeHours;
}
