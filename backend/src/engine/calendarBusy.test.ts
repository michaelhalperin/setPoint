import { describe, expect, it } from 'vitest';
import {
  applyCalendarShift,
  DEFAULT_CALENDAR_PREFS,
  headsUpCopy,
  qualifyingBusyBlocks,
  shiftDueForBusy,
  toMinuteBlocks,
  withOverdue,
} from './calendarBusy.js';
import type { ScheduledCheckIn } from './mealSchedule.js';

const times = { breakfastMin: 480, lunchMin: 780, dinnerMin: 1140 };
const prefsOn = { ...DEFAULT_CALENDAR_PREFS, enabled: true };

describe('qualifyingBusyBlocks', () => {
  const blocks = [
    { startMin: 720, endMin: 900 },
    { startMin: 600, endMin: 630 },
    { startMin: 0, endMin: 1440, allDay: true },
  ];

  it('drops short blocks and all-day unless asked', () => {
    expect(qualifyingBusyBlocks(blocks, prefsOn, 1).map((b) => b.startMin)).toEqual([720]);
  });

  it('keeps all-day when includeAllDay is on', () => {
    const kept = qualifyingBusyBlocks(blocks, { ...prefsOn, includeAllDay: true, minBlockMin: 60 }, 1);
    expect(kept.some((b) => b.allDay)).toBe(true);
  });

  it('skips weekends when workdaysOnly', () => {
    expect(qualifyingBusyBlocks(blocks, prefsOn, 0)).toEqual([]);
    expect(qualifyingBusyBlocks(blocks, prefsOn, 6)).toEqual([]);
    expect(qualifyingBusyBlocks(blocks, { ...prefsOn, workdaysOnly: false }, 0)).not.toEqual([]);
  });
});

describe('shiftDueForBusy', () => {
  it('moves lunch earlier when a meeting covers the grace window', () => {
    const shifted = shiftDueForBusy({
      slot: 'lunch',
      mealMin: 780,
      dueMin: 825,
      times,
      blocks: [{ startMin: 720, endMin: 900 }],
      leadMin: 45,
    });
    expect(shifted.dueMin).toBe(675);
    expect(shifted.movedFromMin).toBe(825);
  });

  it('never moves earlier than the previous meal plus 90 minutes', () => {
    const shifted = shiftDueForBusy({
      slot: 'lunch',
      mealMin: 780,
      dueMin: 825,
      times,
      blocks: [{ startMin: 500, endMin: 900 }],
      leadMin: 45,
    });
    expect(shifted.dueMin).toBe(570);
  });

  it('leaves dinner alone when the block does not overlap its window', () => {
    const shifted = shiftDueForBusy({
      slot: 'dinner',
      mealMin: 1140,
      dueMin: 1185,
      times,
      blocks: [{ startMin: 720, endMin: 900 }],
      leadMin: 45,
    });
    expect(shifted.movedFromMin).toBeNull();
    expect(shifted.dueMin).toBe(1185);
  });
});

describe('applyCalendarShift', () => {
  const scheduled: ScheduledCheckIn = {
    slot: 'lunch',
    mealMin: 780,
    dueMin: 825,
    overdue: false,
  };

  it('marks overdue against the earlier due time', () => {
    const shifted = applyCalendarShift(scheduled, times, [{ startMin: 720, endMin: 900 }], prefsOn, 1);
    expect(shifted?.dueMin).toBe(675);
    expect(withOverdue(shifted!, 680).overdue).toBe(true);
    expect(withOverdue(shifted!, 670).overdue).toBe(false);
  });

  it('does nothing when calendar is off', () => {
    const shifted = applyCalendarShift(scheduled, times, [{ startMin: 720, endMin: 900 }], DEFAULT_CALENDAR_PREFS, 1);
    expect(shifted?.movedFromMin).toBeNull();
    expect(shifted?.dueMin).toBe(825);
  });
});

describe('headsUpCopy', () => {
  it('names the busy window in plain language', () => {
    expect(headsUpCopy({ startMin: 720, endMin: 900 }, 'lunch')).toContain('12–3');
    expect(headsUpCopy({ startMin: 720, endMin: 900 }, 'lunch')).toContain('noon');
  });
});

describe('toMinuteBlocks', () => {
  // 2026-09-14 in New York starts at 04:00Z.
  const dayStart = new Date('2026-09-14T04:00:00Z');
  const tz = 'America/New_York';

  it('keeps an all-day event all-day even when its stored start was clipped to the upload time', () => {
    const blocks = toMinuteBlocks(
      [{ start: new Date('2026-09-14T14:00:00Z'), end: new Date('2026-09-15T04:00:00Z'), allDay: true }],
      dayStart,
      tz,
    );
    expect(blocks[0]?.allDay).toBe(true);
    expect(qualifyingBusyBlocks(blocks, prefsOn, 1)).toEqual([]);
  });

  it('does not pull check-ins earlier for an all-day event unless the user opts in', () => {
    const blocks = toMinuteBlocks([{ start: dayStart, end: new Date('2026-09-15T04:00:00Z') }], dayStart, tz);
    const due: ScheduledCheckIn = { slot: 'lunch', mealMin: 780, dueMin: 825, overdue: false };
    expect(applyCalendarShift(due, times, blocks, prefsOn, 1)?.movedFromMin).toBeNull();
    expect(applyCalendarShift(due, times, blocks, { ...prefsOn, includeAllDay: true }, 1)?.movedFromMin).toBe(825);
  });
});
