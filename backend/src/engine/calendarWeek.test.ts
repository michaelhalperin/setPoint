import { describe, expect, it } from 'vitest';
import { DEFAULT_CALENDAR_PREFS, shiftDueForBusy } from './calendarBusy.js';
import { buildCalendarDay, buildCalendarWeek, mondayOffset, type CalendarDayInput } from './calendarWeek.js';

const times = { breakfastMin: 480, lunchMin: 780, dinnerMin: 1140 };
const prefs = { ...DEFAULT_CALENDAR_PREFS, enabled: true };
const workshop = { startMin: 720, endMin: 930 }; // 12:00–15:30

function day(overrides: Partial<CalendarDayInput> = {}): CalendarDayInput {
  return { date: '2026-09-15', weekday: 2, times, blocks: [], meals: [], kept: [], ...overrides };
}

describe('shiftDueForBusy reason', () => {
  it('uses the heads-up lead when the previous meal is long past', () => {
    const shift = shiftDueForBusy({ slot: 'lunch', mealMin: 780, dueMin: 825, times, blocks: [workshop], leadMin: 45 });
    expect(shift).toMatchObject({ dueMin: 675, movedFromMin: 825, reason: 'lead' });
  });

  it('never lands closer than 90 minutes after the previous meal', () => {
    const late = { ...times, breakfastMin: 600 };
    const shift = shiftDueForBusy({ slot: 'lunch', mealMin: 780, dueMin: 825, times: late, blocks: [workshop], leadMin: 45 });
    expect(shift).toMatchObject({ dueMin: 690, reason: 'floor' });
  });
});

describe('buildCalendarDay', () => {
  const ctx = { today: '2026-09-14', nowMin: 600, prefs };

  it('moves lunch to meeting start minus the heads-up', () => {
    const out = buildCalendarDay(day({ blocks: [workshop] }), ctx);
    const lunch = out.meals.find((m) => m.slot === 'lunch')!;
    expect(lunch).toMatchObject({ usualMin: 780, atMin: 675, earlyMin: 675, moved: true, kept: false, canKeep: true, status: 'upcoming' });
    expect(lunch.busy).toEqual({ startMin: 720, endMin: 930 });
    expect(out.meals.find((m) => m.slot === 'dinner')!.moved).toBe(false);
  });

  it('a kept meal stays at its usual time but can still be moved back', () => {
    const lunch = buildCalendarDay(day({ blocks: [workshop], kept: ['lunch'] }), ctx).meals[1]!;
    expect(lunch).toMatchObject({ atMin: 780, earlyMin: 675, moved: false, kept: true, canKeep: true, reason: 'lead' });
  });

  it('marks short blocks as not counting', () => {
    const standup = { startMin: 570, endMin: 585 };
    const out = buildCalendarDay(day({ blocks: [workshop, standup] }), ctx);
    expect(out.blocks).toEqual([
      { startMin: 570, endMin: 585, allDay: false, counts: false },
      { startMin: 720, endMin: 930, allDay: false, counts: true },
    ]);
  });

  it('reads done / missed / upcoming from meals and the clock', () => {
    const today = { today: '2026-09-15', nowMin: 700, prefs };
    const out = buildCalendarDay(day({ meals: [{ minuteOfDay: 485, kcal: 520 }] }), today);
    expect(out.meals.map((m) => m.status)).toEqual(['done', 'upcoming', 'upcoming']);
    expect(out.meals[0]).toMatchObject({ loggedMin: 485, kcal: 520 });

    const moved = buildCalendarDay(day({ blocks: [workshop] }), today);
    expect(moved.meals[1]!.status).toBe('missed'); // 11:15 has passed with nothing logged

    const past = buildCalendarDay(day({ date: '2026-09-14', weekday: 1 }), today);
    expect(past.meals.every((m) => m.status === 'missed')).toBe(true);
  });

  it('ignores busy time on weekends when workdays only', () => {
    const out = buildCalendarDay(day({ weekday: 6, blocks: [workshop] }), ctx);
    expect(out.meals.some((m) => m.moved)).toBe(false);
    expect(out.blocks[0]!.counts).toBe(false);
  });
});

describe('buildCalendarWeek', () => {
  it('counts moved meals and finds the next one ahead', () => {
    const week = buildCalendarWeek({
      week: [
        day({ date: '2026-09-14', weekday: 1, blocks: [workshop] }),
        day({ date: '2026-09-15', weekday: 2, blocks: [workshop] }),
        day({ date: '2026-09-17', weekday: 4, blocks: [{ startMin: 1080, endMin: 1200 }] }),
      ],
      today: '2026-09-14',
      nowMin: 700,
      prefs,
    });
    expect(week.movedCount).toBe(3);
    expect(week.next).toMatchObject({ date: '2026-09-15', slot: 'lunch', atMin: 675, usualMin: 780 });
  });

  it('looks past Sunday for the next move', () => {
    const week = buildCalendarWeek({
      week: [day({ date: '2026-09-20', weekday: 0 })],
      lookahead: [day({ date: '2026-09-21', weekday: 1, blocks: [workshop] })],
      today: '2026-09-20',
      nowMin: 600,
      prefs,
    });
    expect(week.movedCount).toBe(0);
    expect(week.next?.date).toBe('2026-09-21');
  });

  it('returns nothing when the calendar is off', () => {
    const week = buildCalendarWeek({
      week: [day({ blocks: [workshop] })],
      today: '2026-09-15',
      nowMin: 0,
      prefs: DEFAULT_CALENDAR_PREFS,
    });
    expect(week).toMatchObject({ movedCount: 0, next: null });
  });
});

describe('mondayOffset', () => {
  it('walks back to Monday', () => {
    expect([1, 2, 0, 6].map(mondayOffset)).toEqual([-0, -1, -6, -5]);
  });
});
