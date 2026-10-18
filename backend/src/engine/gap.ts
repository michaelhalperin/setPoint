/**
 * Closing the daily gap — the core loop for people who train and can't eat
 * enough. A logged meal is not the same as enough food: a 250 kcal lunch
 * "covers" lunch on the old schedule but leaves the day badly behind.
 *
 * Pure and deterministic (§7). Three questions, all answered from the day's
 * target and what's been eaten:
 *   - is a logged meal too light for where the day should be by now?
 *   - is it evening with the day still well short (one close-the-gap check-in)?
 *   - how big should a top-up after a meal be?
 */
import { expectedThroughSlot, type MealTimes, type SlotName } from './mealSchedule.js';

export const GAP_CONFIG = {
  /**
   * A logged meal only covers its slot when the day has reached this share of
   * the intake expected through that slot. Below it, the meal reads as light.
   */
  coverShare: 0.75,
  /** A light meal only becomes a push when the day is at least this far behind. */
  minLightGapKcal: 300,
  /** Slots where a light meal can become a push. Breakfast is left to the in-app top-up. */
  lightSlots: ['lunch', 'dinner'] as SlotName[],

  /** The evening check-in comes this long after the usual dinner time… */
  closeOffsetMin: 90,
  /** …but never later than this long before quiet hours start. */
  closeBeforeQuietMin: 30,
  /** Only when the day is still at least this short. */
  closeMinGapKcal: 300,
  /** The plate it suggests never asks for more than this (the solver's largest meal). */
  closeMaxKcal: 700,
  /** Nothing closes the day within this long of the previous check-in. */
  closeSpacingMin: 60,

  /** An in-app top-up is offered when the day is at least this far behind pace… */
  topUpMinKcal: 150,
  /** …and never asks for more than this in one go. */
  topUpMaxKcal: 500,

  /** Check-ins of any kind (not the tier-3 conversation) per local day. */
  maxCheckInsPerDay: 4,
} as const;

export type GapConfig = typeof GAP_CONFIG;

/**
 * A slot with something logged is still light when the day is behind the
 * share expected through it. Returns the shortfall, or 0 when it's covered.
 */
export function lightShortfall(input: {
  slot: SlotName;
  consumedKcal: number;
  targetKcal: number;
  extra: boolean;
  config?: GapConfig;
}): number {
  const config = input.config ?? GAP_CONFIG;
  const expected = expectedThroughSlot(input.slot, input.targetKcal, input.extra);
  if (input.consumedKcal >= expected * config.coverShare) return 0;
  return Math.max(0, expected - input.consumedKcal);
}

export type CloseCheckIn = {
  /** When the evening check-in comes, minutes from local midnight. */
  dueMin: number;
  /** kcal still to eat today. */
  gapKcal: number;
  /** The size of plate it asks for (gap, capped). */
  plateKcal: number;
  overdue: boolean;
};

/** When the day's close-the-gap check-in would come, ignoring whether it's due. */
export function closeDueMin(times: MealTimes, quietStartMin: number, config: GapConfig = GAP_CONFIG): number {
  const latest = quietStartMin - config.closeBeforeQuietMin;
  const preferred = times.dinnerMin + config.closeOffsetMin;
  // Quiet hours that start after midnight (e.g. 01:00) don't pull it earlier.
  return latest > times.dinnerMin ? Math.min(preferred, latest) : preferred;
}

/**
 * The evening check-in: once per day, after dinner has had its chance, when
 * the day is still well short. Null when it isn't owed today.
 */
export function closeCheckIn(input: {
  nowMin: number;
  times: MealTimes;
  quietStartMin: number;
  consumedKcal: number;
  targetKcal: number;
  /** A close check-in already went out today. */
  closedToday: boolean;
  /** Minutes since the last check-in of any kind today; null when there was none. */
  minSinceLastCheckIn: number | null;
  config?: GapConfig;
}): CloseCheckIn | null {
  const config = input.config ?? GAP_CONFIG;
  if (input.closedToday) return null;
  const gapKcal = Math.round(input.targetKcal - input.consumedKcal);
  if (gapKcal < config.closeMinGapKcal) return null;
  const dueMin = closeDueMin(input.times, input.quietStartMin, config);
  if (input.minSinceLastCheckIn !== null && input.minSinceLastCheckIn < config.closeSpacingMin) {
    return { dueMin, gapKcal, plateKcal: Math.min(gapKcal, config.closeMaxKcal), overdue: false };
  }
  return {
    dueMin,
    gapKcal,
    plateKcal: Math.min(gapKcal, config.closeMaxKcal),
    overdue: input.nowMin >= dueMin,
  };
}

export type TopUpGap = {
  /** The slot the last meal landed in. */
  slot: SlotName;
  /** How far behind the expected intake through that slot. */
  behindKcal: number;
  /** What the top-up asks for (capped). */
  topUpKcal: number;
};

/**
 * After a meal: is the day behind where it should be by the end of the slot
 * the user just ate in? Null when nothing's been logged in the current slot
 * yet (that's a check-in's job) or the day is on pace.
 */
export function topUpGap(input: {
  /** The slot `nowMin` sits in. */
  currentSlot: SlotName;
  /** Something has been logged in the current slot. */
  loggedInSlot: boolean;
  consumedKcal: number;
  targetKcal: number;
  extra: boolean;
  config?: GapConfig;
}): TopUpGap | null {
  const config = input.config ?? GAP_CONFIG;
  if (!input.loggedInSlot) return null;
  if (input.consumedKcal >= input.targetKcal) return null;
  const expected = expectedThroughSlot(input.currentSlot, input.targetKcal, input.extra);
  const behindKcal = Math.round(expected - input.consumedKcal);
  if (behindKcal < config.topUpMinKcal) return null;
  return { slot: input.currentSlot, behindKcal, topUpKcal: Math.min(behindKcal, config.topUpMaxKcal) };
}

/** Whether today's check-in budget is spent. Tier-3 conversations don't count. */
export function dailyCapReached(
  todayCheckIns: { tier: number }[],
  config: GapConfig = GAP_CONFIG,
): boolean {
  return todayCheckIns.filter((c) => c.tier < 3).length >= config.maxCheckInsPerDay;
}
