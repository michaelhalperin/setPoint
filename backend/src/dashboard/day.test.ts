import { describe, expect, it } from 'vitest';
import { buildDay, type DayInput } from './day.js';

// 08:00 / 13:00 / 19:00 → slot boundaries at 10:30 and 16:00.
const times = { breakfastMin: 480, lunchMin: 780, dinnerMin: 1140 };

const input = (over: Partial<DayInput> = {}): DayInput => ({
  nowMin: 750,
  mealTimes: times,
  meals: [],
  targetKcal: 3000,
  consumedKcal: 0,
  framingState: 'under',
  enforcementEnabled: true,
  ...over,
});

const states = (day: ReturnType<typeof buildDay>) => day.slots.map((s) => [s.slot, s.state]);

describe('buildDay slots', () => {
  it('puts each meal in the slot whose usual time it is closest to', () => {
    const day = buildDay(
      input({
        nowMin: 1000,
        meals: [
          { id: 'late-breakfast', minuteOfDay: 600, kcal: 400 }, // 10:00
          { id: 'early-lunch', minuteOfDay: 770, kcal: 700 }, // 12:50
          { id: 'snack', minuteOfDay: 900, kcal: 200 }, // 15:00
          { id: 'early-dinner', minuteOfDay: 990, kcal: 800 }, // 16:30
        ],
      }),
    );
    expect(day.slots.map((s) => [s.slot, s.mealIds, s.kcal])).toEqual([
      ['breakfast', ['late-breakfast'], 400],
      ['lunch', ['early-lunch', 'snack'], 900],
      ['dinner', ['early-dinner'], 800],
    ]);
  });

  it('marks what is logged, due now, missed, and still to come', () => {
    expect(states(buildDay(input({ nowMin: 750, meals: [{ id: 'm', minuteOfDay: 500, kcal: 500 }] })))).toEqual([
      ['breakfast', 'logged'],
      ['lunch', 'now'],
      ['dinner', 'upcoming'],
    ]);
    expect(states(buildDay(input({ nowMin: 660 })))).toEqual([
      ['breakfast', 'missed'],
      ['lunch', 'upcoming'],
      ['dinner', 'upcoming'],
    ]);
    expect(states(buildDay(input({ nowMin: 1100 })))).toEqual([
      ['breakfast', 'missed'],
      ['lunch', 'missed'],
      ['dinner', 'now'],
    ]);
  });
});

describe('buildDay pace', () => {
  it('ramps expected intake in around each meal time', () => {
    const expected = (nowMin: number) => buildDay(input({ nowMin })).pace!.expectedByNowKcal;
    expect(expected(400)).toBe(0);
    expect(expected(540)).toBe(1000); // breakfast fully in
    expect(expected(780)).toBe(1330); // breakfast + a third of lunch's ramp
    expect(expected(1200)).toBe(3000);
  });

  it('reads behind, on pace, and ahead against that expectation', () => {
    const at = (consumedKcal: number) => buildDay(input({ nowMin: 840, consumedKcal })).pace!; // expects 2000
    expect(at(1200)).toMatchObject({ status: 'behind', behindKcal: 800 });
    expect(at(1900)).toMatchObject({ status: 'on_pace', behindKcal: 100 });
    expect(at(2400)).toMatchObject({ status: 'ahead', behindKcal: 0 });
  });

  it('suggests the next open meal, splitting what is left across the open slots', () => {
    expect(buildDay(input({ nowMin: 750, consumedKcal: 600 })).pace!.next).toEqual({
      slot: 'lunch',
      atMin: 780,
      suggestedKcal: 1200,
    });

    const afterLunch = buildDay(
      input({ nowMin: 800, consumedKcal: 1400, meals: [{ id: 'l', minuteOfDay: 790, kcal: 800 }] }),
    );
    expect(afterLunch.pace!.next).toEqual({ slot: 'dinner', atMin: 1140, suggestedKcal: 1600 });
  });

  it('never suggests a tiny meal', () => {
    const day = buildDay(input({ nowMin: 1100, consumedKcal: 2880 }));
    expect(day.pace!.next).toMatchObject({ slot: 'dinner', suggestedKcal: 150 });
  });

  it('has nothing next once no meal time is open or the target is covered', () => {
    const allDone = buildDay(
      input({ nowMin: 1300, consumedKcal: 2000, meals: [{ id: 'd', minuteOfDay: 1200, kcal: 900 }] }),
    );
    expect(allDone.pace!.next).toBeNull();
    expect(buildDay(input({ framingState: 'over', consumedKcal: 3300 })).pace!.next).toBeNull();
    expect(buildDay(input({ framingState: 'on_track', consumedKcal: 2950 })).pace!.next).toBeNull();
  });

  it('drops pace entirely in quiet mode but keeps the slots', () => {
    const day = buildDay(input({ enforcementEnabled: false, nowMin: 900 }));
    expect(day.pace).toBeNull();
    expect(day.slots).toHaveLength(3);
  });
});
