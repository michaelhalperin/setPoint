import {
  checkInSlotAt,
  SCHEDULE_CONFIG,
  SLOT_ORDER,
  slotWindowStart,
  type MealTimes,
  type SlotName,
} from '../engine/mealSchedule.js';

/**
 * The manager's record for the Week screen: per day and meal, whether the user
 * ate on their own, ate after a check-in, or it slipped by — plus one pattern
 * worth fixing (a meal that keeps running late). Pure.
 */

export type SlotMark = 'on_time' | 'after_check_in' | 'missed' | 'open';

export type RecordDay = {
  date: string;
  /** breakfast, lunch, dinner. */
  slots: SlotMark[];
};

export type LatePattern = {
  slot: SlotName;
  lateDays: number;
  ofDays: number;
  /** The usual meal time now, and the one the record suggests. */
  currentMin: number;
  suggestedMin: number;
};

export type WeekRecord = {
  days: RecordDay[];
  onTime: number;
  afterCheckIn: number;
  missed: number;
  /** Check-ins sent in the window (tier-3 conversations excluded). */
  checkIns: number;
  pattern: LatePattern | null;
};

export type RecordInput = {
  /** Local dates, oldest first, ending with today. */
  dates: string[];
  /** Now, minutes from local midnight (for today's still-open meals). */
  nowMin: number;
  times: MealTimes;
  meals: { date: string; minute: number }[];
  checkIns: { date: string; minute: number; status: string; tier: number }[];
  /** Local YYYY-MM-DD the plan started. Days before this are not missed. */
  planStartDate?: string;
};

export const RECORD_CONFIG = {
  /** A meal this late against its usual time counts as late. */
  lateMin: 30,
  /** Weekdays late (of the weekdays with that meal logged) before suggesting a new time. */
  minLateDays: 3,
  /** Never suggest moving a meal by more than this. */
  maxShiftMin: 120,
} as const;

const DINNER_CLOSE = 1440;

function atOf(times: MealTimes, slot: SlotName): number {
  return slot === 'breakfast' ? times.breakfastMin : slot === 'lunch' ? times.lunchMin : times.dinnerMin;
}

function windowEnd(slot: SlotName, times: MealTimes): number {
  if (slot === 'breakfast') return slotWindowStart('lunch', times);
  if (slot === 'lunch') return slotWindowStart('dinner', times);
  return DINNER_CLOSE;
}

function nextMealMin(slot: SlotName, times: MealTimes): number {
  return slot === 'breakfast' ? times.lunchMin : slot === 'lunch' ? times.dinnerMin : DINNER_CLOSE;
}

function isWeekday(iso: string): boolean {
  const day = new Date(`${iso}T12:00:00Z`).getUTCDay();
  return day !== 0 && day !== 6;
}

export function buildWeekRecord(input: RecordInput, config = RECORD_CONFIG): WeekRecord {
  const today = input.dates[input.dates.length - 1];
  const grace = SCHEDULE_CONFIG.graceMin;
  let onTime = 0;
  let afterCheckIn = 0;
  let missed = 0;

  const days: RecordDay[] = input.dates.map((date) => {
    const meals = input.meals.filter((m) => m.date === date);
    const checkIns = input.checkIns.filter((c) => c.date === date && c.tier < 3);
    const slots = SLOT_ORDER.map((slot): SlotMark => {
      const start = slotWindowStart(slot, input.times);
      const end = windowEnd(slot, input.times);
      const ate = meals.some((m) => m.minute >= start && m.minute < end);
      const checkIn = checkIns.find((c) => checkInSlotAt(c.minute, input.times, grace) === slot);

      let mark: SlotMark;
      if (checkIn) {
        if (checkIn.status === 'LOGGED') mark = 'after_check_in';
        else if (checkIn.status === 'PENDING' || checkIn.status === 'DEFERRED') mark = 'open';
        // Resolved without a log: "I already ate" or the day's target was met.
        else if (checkIn.status === 'EXPIRED') mark = 'on_time';
        else mark = 'missed';
      } else if (ate) {
        mark = 'on_time';
      } else if (
        (input.planStartDate != null && date < input.planStartDate) ||
        (date === today && input.nowMin < nextMealMin(slot, input.times))
      ) {
        // Before the plan existed, or this meal hasn't come yet today.
        mark = 'open';
      } else {
        mark = 'missed';
      }

      if (mark === 'on_time') onTime += 1;
      else if (mark === 'after_check_in') afterCheckIn += 1;
      else if (mark === 'missed') missed += 1;
      return mark;
    });
    return { date, slots };
  });

  return {
    days,
    onTime,
    afterCheckIn,
    missed,
    checkIns: input.checkIns.filter((c) => c.tier < 3 && input.dates.includes(c.date)).length,
    pattern: latePattern(input, config),
  };
}

/** The meal that most often runs late on past weekdays, with a better time for it. */
function latePattern(input: RecordInput, config: typeof RECORD_CONFIG): LatePattern | null {
  const today = input.dates[input.dates.length - 1];
  const weekdays = input.dates.filter((d) => d !== today && isWeekday(d));
  let best: LatePattern | null = null;

  for (const slot of SLOT_ORDER) {
    const at = atOf(input.times, slot);
    const start = slotWindowStart(slot, input.times);
    const end = windowEnd(slot, input.times);
    const lateness: number[] = [];
    let ofDays = 0;
    for (const date of weekdays) {
      const first = input.meals
        .filter((m) => m.date === date && m.minute >= start && m.minute < end)
        .map((m) => m.minute)
        .sort((a, b) => a - b)[0];
      if (first === undefined) continue;
      ofDays += 1;
      if (first - at >= config.lateMin) lateness.push(first - at);
    }
    if (lateness.length < config.minLateDays || lateness.length * 5 < ofDays * 3) continue;

    const sorted = [...lateness].sort((a, b) => a - b);
    const median = sorted[Math.floor((sorted.length - 1) / 2)]!; // the lower middle: conservative
    const shift = Math.min(config.maxShiftMin, Math.round(median / 15) * 15);
    const suggestedMin = at + shift;
    if (suggestedMin >= nextMealMin(slot, input.times) - 60) continue;

    if (!best || lateness.length > best.lateDays) {
      best = { slot, lateDays: lateness.length, ofDays, currentMin: at, suggestedMin };
    }
  }
  return best;
}
