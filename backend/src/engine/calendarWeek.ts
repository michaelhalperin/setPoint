import {
  qualifyingBusyBlocks,
  shiftDueForBusy,
  type CalendarPrefs,
  type MinuteBlock,
  type ShiftReason,
} from './calendarBusy.js';
import { SCHEDULE_CONFIG, SLOT_ORDER, slotWindowStart, type CoreSlot, type MealTimes } from './mealSchedule.js';

/**
 * The Calendar week screen: for each local day, which busy stretches count,
 * where each meal lands, and whether it was eaten. Pure — the route loads rows,
 * this decides.
 */

export type CalendarDayInput = {
  /** Local YYYY-MM-DD. */
  date: string;
  /** 0 = Sunday … 6 = Saturday. */
  weekday: number;
  times: MealTimes;
  /** Every uploaded busy interval clipped to this day, qualifying or not. */
  blocks: MinuteBlock[];
  meals: { minuteOfDay: number; kcal: number }[];
  /** Slots the user chose to keep at their usual time on this day. */
  kept: string[];
};

export type CalendarMealStatus = 'done' | 'missed' | 'upcoming';

export type CalendarDayMeal = {
  slot: CoreSlot;
  usualMin: number;
  /** When the meal (and its heads-up) is planned: the moved time, or the usual time. */
  atMin: number;
  moved: boolean;
  reason: ShiftReason | null;
  kept: boolean;
  /** Busy time would move this meal — show the Keep / Move earlier choice. */
  canKeep: boolean;
  /** Where busy time puts it, kept or not (null when nothing moves it). */
  earlyMin: number | null;
  busy: { startMin: number; endMin: number } | null;
  status: CalendarMealStatus;
  loggedMin: number | null;
  kcal: number | null;
};

export type CalendarDay = {
  date: string;
  weekday: number;
  blocks: { startMin: number; endMin: number; allDay: boolean; counts: boolean }[];
  meals: CalendarDayMeal[];
};

export type CalendarNext = {
  date: string;
  slot: CoreSlot;
  usualMin: number;
  atMin: number;
  earlyMin: number;
  kept: boolean;
  reason: ShiftReason | null;
  busy: { startMin: number; endMin: number };
};

export type CalendarWeek = {
  days: CalendarDay[];
  movedCount: number;
  next: CalendarNext | null;
};

const CORE_SLOTS = SLOT_ORDER as CoreSlot[];

function usualMinOf(slot: CoreSlot, times: MealTimes): number {
  if (slot === 'breakfast') return times.breakfastMin;
  if (slot === 'lunch') return times.lunchMin;
  return times.dinnerMin;
}

function slotWindowEnd(slot: CoreSlot, times: MealTimes): number {
  if (slot === 'breakfast') return slotWindowStart('lunch', times);
  if (slot === 'lunch') return slotWindowStart('dinner', times);
  return 1440;
}

export function buildCalendarDay(
  input: CalendarDayInput,
  ctx: { today: string; nowMin: number; prefs: CalendarPrefs; graceMin?: number },
): CalendarDay {
  const graceMin = ctx.graceMin ?? SCHEDULE_CONFIG.graceMin;
  const qualified = qualifyingBusyBlocks(input.blocks, ctx.prefs, input.weekday);
  const kept = new Set(input.kept);

  const meals = CORE_SLOTS.map((slot): CalendarDayMeal => {
    const usualMin = usualMinOf(slot, input.times);
    const shift = shiftDueForBusy({
      slot,
      mealMin: usualMin,
      dueMin: usualMin + graceMin,
      times: input.times,
      blocks: qualified,
      leadMin: ctx.prefs.leadMin,
    });
    const canKeep = shift.movedFromMin != null;
    const isKept = canKeep && kept.has(slot);
    const moved = canKeep && !isKept;

    const windowStart = slotWindowStart(slot, input.times);
    const windowEnd = slotWindowEnd(slot, input.times);
    const eaten = input.meals
      .filter((m) => m.minuteOfDay >= windowStart && m.minuteOfDay < windowEnd)
      .sort((a, b) => a.minuteOfDay - b.minuteOfDay);
    const dueMin = moved ? shift.dueMin : usualMin + graceMin;
    const status: CalendarMealStatus =
      eaten.length > 0
        ? 'done'
        : input.date < ctx.today || (input.date === ctx.today && ctx.nowMin >= dueMin)
          ? 'missed'
          : 'upcoming';

    return {
      slot,
      usualMin,
      atMin: moved ? shift.dueMin : usualMin,
      moved,
      reason: shift.reason,
      kept: isKept,
      canKeep,
      earlyMin: canKeep ? shift.dueMin : null,
      busy: shift.block ? { startMin: shift.block.startMin, endMin: shift.block.endMin } : null,
      status,
      loggedMin: eaten[0]?.minuteOfDay ?? null,
      kcal: eaten.length > 0 ? eaten.reduce((sum, m) => sum + m.kcal, 0) : null,
    };
  });

  return {
    date: input.date,
    weekday: input.weekday,
    blocks: input.blocks
      .slice()
      .sort((a, b) => a.startMin - b.startMin)
      .map((b) => ({ startMin: b.startMin, endMin: b.endMin, allDay: b.allDay === true, counts: qualified.includes(b) })),
    meals,
  };
}

/** The soonest meal still ahead that busy time moves (or would move, if kept). */
export function nextCalendarMove(days: CalendarDay[], today: string, nowMin: number): CalendarNext | null {
  const ordered = days.filter((d) => d.date >= today).sort((a, b) => a.date.localeCompare(b.date));
  for (const day of ordered) {
    for (const meal of day.meals) {
      if (!meal.canKeep || !meal.busy || meal.earlyMin == null || meal.status !== 'upcoming') continue;
      if (day.date === today && meal.atMin <= nowMin) continue;
      return {
        date: day.date,
        slot: meal.slot,
        usualMin: meal.usualMin,
        atMin: meal.atMin,
        earlyMin: meal.earlyMin,
        kept: meal.kept,
        reason: meal.reason,
        busy: meal.busy,
      };
    }
  }
  return null;
}

/**
 * `week` is the seven days drawn on the grid; `lookahead` is any later days
 * (e.g. next Monday on a Sunday) so "Tomorrow" still has something to show.
 */
export function buildCalendarWeek(input: {
  week: CalendarDayInput[];
  lookahead?: CalendarDayInput[];
  today: string;
  nowMin: number;
  prefs: CalendarPrefs;
  graceMin?: number;
}): CalendarWeek {
  const ctx = { today: input.today, nowMin: input.nowMin, prefs: input.prefs, graceMin: input.graceMin };
  const days = input.week.map((d) => buildCalendarDay(d, ctx));
  const extra = (input.lookahead ?? []).map((d) => buildCalendarDay(d, ctx));
  return {
    days,
    movedCount: days.reduce((sum, d) => sum + d.meals.filter((m) => m.moved).length, 0),
    next: nextCalendarMove([...days, ...extra], input.today, input.nowMin),
  };
}

/** Monday of the week containing `weekday` (0 = Sunday), as a day offset from that date. */
export function mondayOffset(weekday: number): number {
  return -((weekday + 6) % 7);
}
