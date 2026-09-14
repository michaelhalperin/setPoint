import { describe, expect, it } from 'vitest';
import {
  checkInSlotAt,
  currentMealSlot,
  DEFAULT_WEEKEND_DAYS,
  dueCheckIn,
  isWeekendDay,
  mealTimesOn,
  resolveMealTimes,
  upcomingCheckIn,
  type ScheduleInput,
} from './mealSchedule.js';
import { localWeekday } from './time.js';

const times = { breakfastMin: 480, lunchMin: 780, dinnerMin: 1140 }; // 8:00 · 13:00 · 19:00

function input(over: Partial<ScheduleInput> = {}): ScheduleInput {
  return {
    nowMin: 720,
    times,
    mealMinutesToday: [485],
    checkedSlotsToday: [],
    consumedKcal: 600,
    targetKcal: 2400,
    ...over,
  };
}

describe('upcomingCheckIn', () => {
  it('points at lunch plus the grace period once breakfast is logged', () => {
    expect(upcomingCheckIn(input())).toEqual({ slot: 'lunch', mealMin: 780, dueMin: 825, overdue: false });
  });

  it('is due, not early: nothing fires before the meal time plus grace', () => {
    expect(dueCheckIn(input({ nowMin: 824 }))).toBeNull();
    expect(dueCheckIn(input({ nowMin: 825 }))).toMatchObject({ slot: 'lunch', overdue: true });
  });

  it('never fires before a meal a user eats on time', () => {
    // Breakfast at 8:05, lunch at 13:10 — the old gap formula fired at ~12:30.
    for (const nowMin of [700, 760, 800, 830, 900]) {
      expect(dueCheckIn(input({ nowMin, mealMinutesToday: nowMin >= 790 ? [485, 790] : [485] }))).toBeNull();
    }
  });

  it('counts a late lunch toward lunch so it does not fire', () => {
    expect(dueCheckIn(input({ nowMin: 870, mealMinutesToday: [485, 700] }))).toBeNull(); // 11:40 is past the 10:30 midpoint
  });

  it('stops waiting on a slot once the next meal time arrives', () => {
    expect(upcomingCheckIn(input({ nowMin: 1150, mealMinutesToday: [485] }))).toEqual({
      slot: 'dinner',
      mealMin: 1140,
      dueMin: 1185,
      overdue: false,
    });
  });

  it('fires at most once per slot per day', () => {
    expect(dueCheckIn(input({ nowMin: 900, checkedSlotsToday: ['lunch'] }))).toBeNull();
    expect(upcomingCheckIn(input({ nowMin: 900, checkedSlotsToday: ['lunch'] }))).toMatchObject({ slot: 'dinner' });
  });

  it('has nothing to say once the day’s target is met', () => {
    expect(upcomingCheckIn(input({ consumedKcal: 2400 }))).toBeNull();
  });

  it('covers breakfast with any meal since midnight', () => {
    expect(upcomingCheckIn(input({ nowMin: 400, mealMinutesToday: [] }))).toMatchObject({ slot: 'breakfast', dueMin: 525 });
    expect(upcomingCheckIn(input({ nowMin: 400, mealMinutesToday: [390] }))).toMatchObject({ slot: 'lunch' });
  });

  it('inserts mid-morning and afternoon slots when extraSlots is on', () => {
    expect(upcomingCheckIn(input({ nowMin: 500, mealMinutesToday: [490], extraSlots: true }))).toMatchObject({
      slot: 'snack_am',
      mealMin: 630,
    });
  });
});

describe('checkInSlotAt', () => {
  it('maps a check-in time back to the meal it was for', () => {
    expect(checkInSlotAt(500, times)).toBeNull();
    expect(checkInSlotAt(525, times)).toBe('breakfast');
    expect(checkInSlotAt(900, times)).toBe('lunch');
    expect(checkInSlotAt(1185, times)).toBe('dinner');
  });
});

describe('currentMealSlot', () => {
  it('uses the same midpoints as Today slot windows', () => {
    expect(currentMealSlot(0, times)).toBe('breakfast');
    expect(currentMealSlot(629, times)).toBe('breakfast'); // just before (480+780)/2 = 630
    expect(currentMealSlot(630, times)).toBe('lunch');
    expect(currentMealSlot(959, times)).toBe('lunch'); // just before (780+1140)/2 = 960
    expect(currentMealSlot(960, times)).toBe('dinner');
    expect(currentMealSlot(1439, times)).toBe('dinner');
  });
});

describe('weekend meal times', () => {
  const weekend = { breakfastMin: 600, lunchMin: 840, dinnerMin: 1200 };

  it('uses weekday times on a Thursday and weekend times on Saturday', () => {
    expect(isWeekendDay(4, DEFAULT_WEEKEND_DAYS)).toBe(false);
    expect(isWeekendDay(6, DEFAULT_WEEKEND_DAYS)).toBe(true);
    expect(resolveMealTimes(times, weekend, DEFAULT_WEEKEND_DAYS, 4)).toEqual(times);
    expect(resolveMealTimes(times, weekend, DEFAULT_WEEKEND_DAYS, 6)).toEqual(weekend);
  });

  it('falls back to weekday minutes when a weekend slot is null', () => {
    expect(
      resolveMealTimes(times, { breakfastMin: 600, lunchMin: null, dinnerMin: null }, DEFAULT_WEEKEND_DAYS, 0),
    ).toEqual({ breakfastMin: 600, lunchMin: 780, dinnerMin: 1140 });
  });

  it('honours a custom weekendDays bitmask (Friday+Saturday)', () => {
    const friSat = 0b1100000; // Fri=5, Sat=6
    expect(isWeekendDay(5, friSat)).toBe(true);
    expect(isWeekendDay(0, friSat)).toBe(false);
    expect(mealTimesOn({ ...times, weekendBreakfastMin: 610, weekendDays: friSat }, 5).breakfastMin).toBe(610);
    expect(mealTimesOn({ ...times, weekendBreakfastMin: 610, weekendDays: friSat }, 0).breakfastMin).toBe(480);
  });

  it('picks the local weekday, not UTC, around midnight in New York', () => {
    // 2026-09-19 03:30 UTC = Friday 23:30 EDT; 04:30 UTC = Saturday 00:30 EDT.
    expect(localWeekday(new Date('2026-09-19T03:30:00Z'), 'America/New_York')).toBe(5);
    expect(localWeekday(new Date('2026-09-19T04:30:00Z'), 'America/New_York')).toBe(6);
    const profile = { ...times, weekendBreakfastMin: 600, weekendDays: DEFAULT_WEEKEND_DAYS };
    expect(mealTimesOn(profile, localWeekday(new Date('2026-09-19T03:30:00Z'), 'America/New_York')).breakfastMin).toBe(
      480,
    );
    expect(mealTimesOn(profile, localWeekday(new Date('2026-09-19T04:30:00Z'), 'America/New_York')).breakfastMin).toBe(
      600,
    );
  });
});
