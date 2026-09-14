import { describe, expect, it } from 'vitest';
import { checkInSlotAt, dueCheckIn, upcomingCheckIn, type ScheduleInput } from './mealSchedule.js';

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
});

describe('checkInSlotAt', () => {
  it('maps a check-in time back to the meal it was for', () => {
    expect(checkInSlotAt(500, times)).toBeNull();
    expect(checkInSlotAt(525, times)).toBe('breakfast');
    expect(checkInSlotAt(900, times)).toBe('lunch');
    expect(checkInSlotAt(1185, times)).toBe('dinner');
  });
});
