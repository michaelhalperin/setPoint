import type { MealTimes } from './expectedGap.js';

/**
 * When a check-in is due: a usual meal time plus a grace period, with nothing
 * logged for that meal and the day's target not yet met. Pure and deterministic
 * (§7) — the app shows the same schedule it runs on ("I'll check in at 13:45").
 */

export type SlotName = 'breakfast' | 'lunch' | 'dinner';

export const SLOT_ORDER: SlotName[] = ['breakfast', 'lunch', 'dinner'];

export const SCHEDULE_CONFIG = {
  /** Minutes after a usual meal time, with nothing logged, before a check-in. */
  graceMin: 45,
} as const;

const MINUTES_PER_DAY = 1440;

export type ScheduleInput = {
  /** Now, minutes from local midnight. */
  nowMin: number;
  times: MealTimes;
  /** Minutes from local midnight of each meal logged today, up to now. */
  mealMinutesToday: number[];
  /** Slots that already had a check-in today (any outcome). */
  checkedSlotsToday: SlotName[];
  consumedKcal: number;
  targetKcal: number;
  graceMin?: number;
};

export type ScheduledCheckIn = {
  slot: SlotName;
  /** The usual meal time. */
  mealMin: number;
  /** When the check-in comes if nothing is logged. */
  dueMin: number;
  /** The due time has already passed (the job will fire on its next run). */
  overdue: boolean;
};

function atOf(times: MealTimes, slot: SlotName): number {
  return slot === 'breakfast' ? times.breakfastMin : slot === 'lunch' ? times.lunchMin : times.dinnerMin;
}

/**
 * Where a slot's meals start counting: halfway from the previous meal time
 * (breakfast counts from midnight). Matches the Today screen's slot boundaries.
 */
export function slotWindowStart(slot: SlotName, times: MealTimes): number {
  if (slot === 'breakfast') return 0;
  if (slot === 'lunch') return Math.floor((times.breakfastMin + times.lunchMin) / 2);
  return Math.floor((times.lunchMin + times.dinnerMin) / 2);
}

/** The next meal time after `slot`, or the end of the day after dinner. */
function slotCloses(slot: SlotName, times: MealTimes): number {
  if (slot === 'breakfast') return times.lunchMin;
  if (slot === 'lunch') return times.dinnerMin;
  return MINUTES_PER_DAY;
}

/**
 * The slot a check-in created at `minute` was for: the latest slot whose due
 * time had passed. Null before breakfast's due time.
 */
export function checkInSlotAt(minute: number, times: MealTimes, graceMin: number = SCHEDULE_CONFIG.graceMin): SlotName | null {
  let found: SlotName | null = null;
  for (const slot of SLOT_ORDER) {
    if (minute >= atOf(times, slot) + graceMin) found = slot;
  }
  return found;
}

/** Whether a meal has already covered `slot` today. */
function covered(slot: SlotName, input: ScheduleInput): boolean {
  const start = slotWindowStart(slot, input.times);
  return input.mealMinutesToday.some((m) => m >= start);
}

/**
 * The check-in that is due right now, or null. At most one per slot per day;
 * a slot stops being due once the next meal time arrives.
 */
export function dueCheckIn(input: ScheduleInput): ScheduledCheckIn | null {
  const next = upcomingCheckIn(input);
  return next?.overdue ? next : null;
}

/**
 * The next check-in the user would get if nothing is logged — the one Today
 * shows ("Next check-in 13:45"). Null once the day is covered.
 */
export function upcomingCheckIn(input: ScheduleInput): ScheduledCheckIn | null {
  if (input.consumedKcal >= input.targetKcal) return null;
  const grace = input.graceMin ?? SCHEDULE_CONFIG.graceMin;
  for (const slot of SLOT_ORDER) {
    const mealMin = atOf(input.times, slot);
    const dueMin = mealMin + grace;
    if (input.nowMin >= slotCloses(slot, input.times)) continue;
    if (input.checkedSlotsToday.includes(slot)) continue;
    if (covered(slot, input)) continue;
    return { slot, mealMin, dueMin, overdue: input.nowMin >= dueMin };
  }
  return null;
}
