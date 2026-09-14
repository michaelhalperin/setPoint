import { SLOT_ORDER, type MealTimes, type ScheduledCheckIn, type SlotName } from './mealSchedule.js';
import { msSinceLocalMidnight } from './time.js';

export type MinuteBlock = {
  startMin: number;
  endMin: number;
  allDay?: boolean;
};

export type CalendarPrefs = {
  enabled: boolean;
  leadMin: number;
  minBlockMin: number;
  workdaysOnly: boolean;
  includeAllDay: boolean;
};

export const DEFAULT_CALENDAR_PREFS: CalendarPrefs = {
  enabled: false,
  leadMin: 45,
  minBlockMin: 60,
  workdaysOnly: true,
  includeAllDay: false,
};

const PREVIOUS_MEAL_GAP_MIN = 90;

export function isWorkday(weekday: number): boolean {
  return weekday !== 0 && weekday !== 6;
}

export function rangesOverlap(aStart: number, aEnd: number, bStart: number, bEnd: number): boolean {
  return aStart < bEnd && bStart < aEnd;
}

export function qualifyingBusyBlocks(
  blocks: MinuteBlock[],
  prefs: CalendarPrefs,
  weekday: number,
): MinuteBlock[] {
  if (!prefs.enabled) return [];
  if (prefs.workdaysOnly && !isWorkday(weekday)) return [];
  return blocks.filter((block) => {
    if (block.allDay && !prefs.includeAllDay) return false;
    return block.endMin - block.startMin >= prefs.minBlockMin;
  });
}

function previousMealMin(slot: SlotName, times: MealTimes): number | null {
  if (slot === 'breakfast') return null;
  if (slot === 'lunch') return times.breakfastMin;
  return times.lunchMin;
}

/**
 * If a qualifying busy block overlaps the slot's window [mealMin, mealMin+grace],
 * the due time moves to blockStart − leadMin, never earlier than the previous
 * meal + 90 minutes.
 */
export function shiftDueForBusy(input: {
  slot: SlotName;
  mealMin: number;
  dueMin: number;
  times: MealTimes;
  blocks: MinuteBlock[];
  leadMin: number;
}): { dueMin: number; movedFromMin: number | null; block: MinuteBlock | null } {
  const overlapping = input.blocks
    .filter((block) => rangesOverlap(input.mealMin, input.dueMin, block.startMin, block.endMin))
    .sort((a, b) => a.startMin - b.startMin);
  const block = overlapping[0];
  if (!block) return { dueMin: input.dueMin, movedFromMin: null, block: null };

  const floor = (previousMealMin(input.slot, input.times) ?? 0) + PREVIOUS_MEAL_GAP_MIN;
  const moved = Math.max(floor, block.startMin - input.leadMin);
  if (moved >= input.dueMin) return { dueMin: input.dueMin, movedFromMin: null, block: null };
  return { dueMin: moved, movedFromMin: input.dueMin, block };
}

export type ShiftedCheckIn = ScheduledCheckIn & {
  movedFromMin: number | null;
  busy: MinuteBlock | null;
};

export function applyCalendarShift(
  scheduled: ScheduledCheckIn | null,
  times: MealTimes,
  blocks: MinuteBlock[],
  prefs: CalendarPrefs,
  weekday: number,
): ShiftedCheckIn | null {
  if (!scheduled) return null;
  const qualified = qualifyingBusyBlocks(blocks, prefs, weekday);
  const shifted = shiftDueForBusy({
    slot: scheduled.slot,
    mealMin: scheduled.mealMin,
    dueMin: scheduled.dueMin,
    times,
    blocks: qualified,
    leadMin: prefs.leadMin,
  });
  return {
    ...scheduled,
    dueMin: shifted.dueMin,
    movedFromMin: shifted.movedFromMin,
    busy: shifted.block,
  };
}

/** Recalculate overdue against a possibly earlier due time. */
export function withOverdue(scheduled: ShiftedCheckIn, nowMin: number): ShiftedCheckIn {
  return { ...scheduled, overdue: nowMin >= scheduled.dueMin };
}

export function prefsFromProfile(profile: {
  calendarEnabled?: boolean | null;
  calendarLeadMin?: number | null;
  calendarMinBlockMin?: number | null;
  calendarWorkdaysOnly?: boolean | null;
  calendarIncludeAllDay?: boolean | null;
}): CalendarPrefs {
  return {
    enabled: profile.calendarEnabled ?? DEFAULT_CALENDAR_PREFS.enabled,
    leadMin: profile.calendarLeadMin ?? DEFAULT_CALENDAR_PREFS.leadMin,
    minBlockMin: profile.calendarMinBlockMin ?? DEFAULT_CALENDAR_PREFS.minBlockMin,
    workdaysOnly: profile.calendarWorkdaysOnly ?? DEFAULT_CALENDAR_PREFS.workdaysOnly,
    includeAllDay: profile.calendarIncludeAllDay ?? DEFAULT_CALENDAR_PREFS.includeAllDay,
  };
}

export function movedSlotsToday(
  times: MealTimes,
  graceMin: number,
  blocks: MinuteBlock[],
  prefs: CalendarPrefs,
  weekday: number,
): { slot: SlotName; fromMin: number; toMin: number }[] {
  const qualified = qualifyingBusyBlocks(blocks, prefs, weekday);
  const moved: { slot: SlotName; fromMin: number; toMin: number }[] = [];
  for (const slot of SLOT_ORDER) {
    const mealMin = slot === 'breakfast' ? times.breakfastMin : slot === 'lunch' ? times.lunchMin : times.dinnerMin;
    const dueMin = mealMin + graceMin;
    const shifted = shiftDueForBusy({ slot, mealMin, dueMin, times, blocks: qualified, leadMin: prefs.leadMin });
    if (shifted.movedFromMin != null) {
      moved.push({ slot, fromMin: mealMin, toMin: shifted.dueMin });
    }
  }
  return moved;
}

/** "Meetings 12–3 today. Eat before noon — grab something now." */
export function headsUpCopy(block: MinuteBlock, slot: SlotName): string {
  const range = formatBusyRange(block.startMin, block.endMin);
  const before = block.startMin <= 12 * 60 ? 'noon' : formatClock(block.startMin);
  const meal = slot === 'breakfast' ? 'Breakfast' : slot === 'lunch' ? 'Lunch' : 'Dinner';
  return `Meetings ${range} today. Eat before ${before} — ${meal.toLowerCase()} will be easier if it's already done.`;
}

export function formatBusyRange(startMin: number, endMin: number): string {
  return `${formatClock(startMin)}–${formatClock(endMin)}`;
}

function formatClock(min: number): string {
  const wrapped = ((min % 1440) + 1440) % 1440;
  const h = Math.floor(wrapped / 60);
  const m = wrapped % 60;
  const hour12 = h % 12 === 0 ? 12 : h % 12;
  if (m === 0) return String(hour12);
  return `${hour12}:${m.toString().padStart(2, '0')}`;
}

export function slotNameOf(value: string | null | undefined): SlotName | null {
  if (value === 'breakfast' || value === 'lunch' || value === 'dinner') return value;
  return null;
}

/** Clip UTC busy intervals onto a local day and express them as minutes from midnight. */
export function toMinuteBlocks(
  blocks: { start: Date; end: Date }[],
  dayStart: Date,
  timezone: string,
): MinuteBlock[] {
  const dayEnd = new Date(dayStart.getTime() + 24 * 60 * 60 * 1000);
  const out: MinuteBlock[] = [];
  for (const block of blocks) {
    const start = new Date(Math.max(block.start.getTime(), dayStart.getTime()));
    const end = new Date(Math.min(block.end.getTime(), dayEnd.getTime()));
    if (end <= start) continue;
    const startMin = Math.floor(msSinceLocalMidnight(start, timezone) / 60_000);
    let endMin = Math.ceil(msSinceLocalMidnight(end, timezone) / 60_000);
    if (end.getTime() >= dayEnd.getTime()) endMin = 1440;
    if (endMin <= startMin) continue;
    out.push({
      startMin,
      endMin,
      allDay: block.start <= dayStart && block.end >= dayEnd,
    });
  }
  return out;
}
