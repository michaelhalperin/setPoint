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
  /**
   * A log under this many kcal (a coffee, a sip of juice) is not a meal: it doesn't cover its
   * slot and doesn't restart the "time since you last ate" clock. It still counts toward the day.
   */
  minMealKcal: 100,
} as const;

/** Whether a logged item is big enough to count as having eaten a meal. */
export function countsAsMeal(kcal: number): boolean {
  return kcal >= SCHEDULE_CONFIG.minMealKcal;
}

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
  /**
   * A logged meal only covers its slot when the day is near the intake
   * expected through it (see `engine/gap.ts`). Absent: any log covers the slot.
   */
  lightRule?: LightRule;
};

/** When a logged-but-small meal still leaves its slot open. Pass `GAP_CONFIG`. */
export type LightRule = {
  coverShare: number;
  minLightGapKcal: number;
  lightSlots: readonly SlotName[];
};

export type ScheduledCheckIn = {
  slot: SlotName;
  /** The usual meal time. */
  mealMin: number;
  /** When the check-in comes if nothing is logged. */
  dueMin: number;
  /** The due time has already passed (the job will fire on its next run). */
  overdue: boolean;
  /** Something was logged for this meal, but too little for where the day should be. */
  light?: boolean;
};

/** kcal the day's equal meal shares expect by the end of `slot`. */
export function expectedThroughSlot(slot: SlotName, targetKcal: number, extra: boolean): number {
  const order = extra ? APPETITE_SLOT_ORDER : SLOT_ORDER;
  const idx = order.indexOf(slot);
  if (idx < 0) return targetKcal;
  return Math.round((targetKcal * (idx + 1)) / order.length);
}

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

/** Minutes of today's meals logged for `slot` (from its window start on). */
function mealsInSlot(slot: SlotName, input: ScheduleInput): number[] {
  const start = slotWindowStart(slot, input.times);
  return input.mealMinutesToday.filter((m) => m >= start);
}

/** A slot with a log that's still too light for where the day should be by now. */
function isLight(slot: SlotName, input: ScheduleInput, extra: boolean): boolean {
  const rule = input.lightRule;
  if (!rule || !rule.lightSlots.includes(slot)) return false;
  const expected = expectedThroughSlot(slot, input.targetKcal, extra);
  if (input.consumedKcal >= expected * rule.coverShare) return false;
  return expected - input.consumedKcal >= rule.minLightGapKcal;
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
    const logged = mealsInSlot(slot, input);
    if (logged.length > 0) {
      if (!isLight(slot, input, extra)) continue;
      // Give the meal time to land before asking for more.
      const lightDue = Math.max(dueMin, Math.max(...logged) + grace);
      return { slot, mealMin, dueMin: lightDue, overdue: input.nowMin >= lightDue, light: true };
    }
    return { slot, mealMin, dueMin, overdue: input.nowMin >= dueMin };
  }
  return null;
}
