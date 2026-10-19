import { describe, expect, it } from 'vitest';
import { nutritionOverview, personDays, weightTrends } from './nutrition.js';

const tz = 'Asia/Jerusalem';

describe('personDays', () => {
  const now = new Date('2026-10-19T12:00:00Z'); // 15:00 in Tel Aviv
  const person = { timezone: tz, kcalTarget: 3000, proteinTargetG: 150 };

  it('sums each local day and uses the settled target when there is one', () => {
    const meals = [
      { userId: 'u', loggedAt: new Date('2026-10-19T06:00:00Z'), kcal: 700, proteinG: 40 },
      { userId: 'u', loggedAt: new Date('2026-10-19T10:00:00Z'), kcal: 900, proteinG: 55.4 },
      // 23:30 local on the 18th, 20:30 UTC
      { userId: 'u', loggedAt: new Date('2026-10-18T20:30:00Z'), kcal: 500, proteinG: 20 },
    ];
    const outcomes = [{ userId: 'u', date: new Date('2026-10-18'), kind: 'UNDER', kcalConsumed: 500, kcalTarget: 3300 }];
    const days = personDays(meals, person, outcomes, 3, now);
    expect(days.map((d) => d.date)).toEqual(['2026-10-17', '2026-10-18', '2026-10-19']);
    expect(days[1]).toMatchObject({ kcal: 500, targetKcal: 3300, kind: 'UNDER', meals: 1 });
    expect(days[2]).toMatchObject({ kcal: 1600, proteinG: 95, targetKcal: 3000, kind: 'TODAY', meals: 2 });
    expect(days[0]).toMatchObject({ kcal: 0, meals: 0, kind: null });
  });
});

describe('nutritionOverview', () => {
  it('averages settled days against target, counting missed days apart', () => {
    const outcomes = [
      { userId: 'a', date: new Date('2026-10-17'), kind: 'ON_TRACK', kcalConsumed: 2900, kcalTarget: 3000 },
      { userId: 'b', date: new Date('2026-10-17'), kind: 'UNDER', kcalConsumed: 1500, kcalTarget: 3000 },
      { userId: 'b', date: new Date('2026-10-18'), kind: 'MISSED', kcalConsumed: 0, kcalTarget: 3000 },
    ];
    const meals = [
      { userId: 'a', loggedAt: new Date('2026-10-17T08:00:00Z'), kcal: 1000, proteinG: 60 },
      { userId: 'a', loggedAt: new Date('2026-10-17T15:00:00Z'), kcal: 1900, proteinG: 90 },
      { userId: 'b', loggedAt: new Date('2026-10-17T15:00:00Z'), kcal: 1500, proteinG: 50 },
    ];
    const targets = new Map([
      ['a', { timezone: tz, kcalTarget: 3000, proteinTargetG: 150 }],
      ['b', { timezone: tz, kcalTarget: 3000, proteinTargetG: 100 }],
    ]);
    const r = nutritionOverview(outcomes, meals, targets);
    expect(r.calories.avgShareOfTarget).toBeCloseTo((2900 / 3000 + 0.5) / 2);
    expect(r.calories.missedDays).toBe(1);
    expect(r.calories.daily).toEqual([{ date: '2026-10-17', avgShareOfTarget: r.calories.avgShareOfTarget, people: 2 }]);
    expect(r.protein.avgShareOfTarget).toBeCloseTo((150 / 150 + 50 / 100) / 2);
    expect(r.protein.avgGramsPerDay).toBe(100);
  });
});

describe('weightTrends', () => {
  it('gives kg per week for people with two weigh-ins three or more days apart, by goal', () => {
    const rows = [
      { userId: 'a', weightKg: 70, measuredAt: new Date('2026-10-01') },
      { userId: 'a', weightKg: 70.6, measuredAt: new Date('2026-10-15') },
      { userId: 'b', weightKg: 80, measuredAt: new Date('2026-10-14') },
      { userId: 'b', weightKg: 80.2, measuredAt: new Date('2026-10-15') },
      { userId: 'c', weightKg: 90, measuredAt: new Date('2026-10-01') },
    ];
    const r = weightTrends(rows, new Map([['a', 'BULK'], ['b', 'BULK']]));
    expect(r.people).toBe(1);
    expect(r.avgKgPerWeek).toBe(0.3);
    expect(r.byGoal).toEqual({ BULK: { people: 1, avgKgPerWeek: 0.3 } });
  });
});
