/**
 * When a check-in is due: a usual meal time plus a grace period, with nothing
 * logged for that meal and the day's target not yet met. Pure and deterministic
 * (§7) — the app shows the same schedule it runs on ("I'll check in at 13:45").
 */

export type MealTimes = {
  /** Minutes from local midnight. */
  breakfastMin: number;
  lunchMin: number;
  dinnerMin: number;
};

/** Per-slot override. Null = same as the weekday time. */
export type WeekendMealTimes = {
  breakfastMin: number | null;
  lunchMin: number | null;
  dinnerMin: number | null;
};

/** Stored on the profile so scoring, Home and Week share one selector. */
export type ScheduleProfile = MealTimes & {
  weekendBreakfastMin?: number | null;
  weekendLunchMin?: number | null;
  weekendDinnerMin?: number | null;
  weekendDays?: number | null;
};

/** bit 0 = Sunday … bit 6 = Saturday. Default Sat+Sun. */
export const DEFAULT_WEEKEND_DAYS = 0b1000001;

export function isWeekendDay(weekday: number, weekendDays: number = DEFAULT_WEEKEND_DAYS): boolean {
  return ((weekendDays >> (weekday % 7)) & 1) === 1;
}

export function resolveMealTimes(
  weekdayTimes: MealTimes,
  weekend: WeekendMealTimes | null | undefined,
  weekendDays: number,
  weekday: number,
): MealTimes {
  if (!isWeekendDay(weekday, weekendDays)) return weekdayTimes;
  return {
    breakfastMin: weekend?.breakfastMin ?? weekdayTimes.breakfastMin,
    lunchMin: weekend?.lunchMin ?? weekdayTimes.lunchMin,
    dinnerMin: weekend?.dinnerMin ?? weekdayTimes.dinnerMin,
  };
}

export function mealTimesOn(profile: ScheduleProfile, weekday: number): MealTimes {
  return resolveMealTimes(
    { breakfastMin: profile.breakfastMin, lunchMin: profile.lunchMin, dinnerMin: profile.dinnerMin },
    {
      breakfastMin: profile.weekendBreakfastMin ?? null,
      lunchMin: profile.weekendLunchMin ?? null,
      dinnerMin: profile.weekendDinnerMin ?? null,
    },
    profile.weekendDays ?? DEFAULT_WEEKEND_DAYS,
    weekday,
  );
}

export type CoreSlot = 'breakfast' | 'lunch' | 'dinner';
export type SlotName = CoreSlot | 'snack_am' | 'snack_pm';

export const SLOT_ORDER: SlotName[] = ['breakfast', 'lunch', 'dinner'];
export const APPETITE_SLOT_ORDER: SlotName[] = ['breakfast', 'snack_am', 'lunch', 'snack_pm', 'dinner'];

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
  /** Extra mid-morning / afternoon check-ins (SMALL_FREQUENT / LOW). */
  extraSlots?: boolean;
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
  if (slot === 'breakfast') return times.breakfastMin;
  if (slot === 'lunch') return times.lunchMin;
  if (slot === 'dinner') return times.dinnerMin;
  if (slot === 'snack_am') return Math.floor((times.breakfastMin + times.lunchMin) / 2);
  return Math.floor((times.lunchMin + times.dinnerMin) / 2);
}

/**
 * Where a slot's meals start counting: halfway from the previous meal time
 * (breakfast counts from midnight). Matches the Today screen's slot boundaries.
 */
export function slotWindowStart(slot: SlotName, times: MealTimes): number {
  if (slot === 'breakfast') return 0;
  if (slot === 'snack_am') return Math.floor((times.breakfastMin + atOf(times, 'snack_am')) / 2);
  if (slot === 'lunch') return Math.floor((times.breakfastMin + times.lunchMin) / 2);
  if (slot === 'snack_pm') return Math.floor((times.lunchMin + atOf(times, 'snack_pm')) / 2);
  return Math.floor((times.lunchMin + times.dinnerMin) / 2);
}

/**
 * The meal window `nowMin` sits in: breakfast from midnight until the lunch
 * midpoint, lunch until the dinner midpoint, dinner after that.
 */
export function currentMealSlot(nowMin: number, times: MealTimes): SlotName {
  if (nowMin < slotWindowStart('lunch', times)) return 'breakfast';
  if (nowMin < slotWindowStart('dinner', times)) return 'lunch';
  return 'dinner';
}

/** The next meal time after `slot`, or the end of the day after dinner. */
function slotCloses(slot: SlotName, times: MealTimes, extra: boolean): number {
  const order = extra ? APPETITE_SLOT_ORDER : SLOT_ORDER;
  const idx = order.indexOf(slot);
  if (idx < 0 || idx === order.length - 1) return MINUTES_PER_DAY;
  return atOf(times, order[idx + 1]!);
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
  const extra = input.extraSlots === true;
  const order = extra ? APPETITE_SLOT_ORDER : SLOT_ORDER;
  for (const slot of order) {
    const mealMin = atOf(input.times, slot);
    const dueMin = mealMin + grace;
    if (input.nowMin >= slotCloses(slot, input.times, extra)) continue;
    if (input.checkedSlotsToday.includes(slot)) continue;
    if (covered(slot, input)) continue;
    return { slot, mealMin, dueMin, overdue: input.nowMin >= dueMin };
  }
  return null;
}
