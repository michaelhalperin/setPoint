import { clamp } from './types.js';

export type MealTimes = {
  /** Minutes from local midnight. */
  breakfastMin: number;
  lunchMin: number;
  dinnerMin: number;
};

const DEFAULT_GAP_HOURS = 5;
const MIN_GAP_HOURS = 3;
const MAX_GAP_HOURS = 10;

/** A minute-gap `<= 0` means the later meal wraps past midnight; add a day. */
const wrap = (minutes: number): number => (minutes <= 0 ? minutes + 1440 : minutes);

/**
 * The user's expected inter-meal gap in hours, derived purely from their own
 * onboarding meal times (plan §2: "derived per-user from their own
 * onboarding-set meal times, not a global constant").
 *
 * v1: mean of the two daytime gaps (breakfast→lunch, lunch→dinner), clamped to
 * a sane range. Handles unusual schedules (shift work) via the midnight wrap
 * without special-casing.
 */
export function expectedGapHours(times: MealTimes): number {
  const morningGap = wrap(times.lunchMin - times.breakfastMin);
  const afternoonGap = wrap(times.dinnerMin - times.lunchMin);
  const meanHours = (morningGap + afternoonGap) / 2 / 60;

  if (!Number.isFinite(meanHours) || meanHours <= 0) return DEFAULT_GAP_HOURS;
  return clamp(meanHours, MIN_GAP_HOURS, MAX_GAP_HOURS);
}
