import { describe, expect, it } from 'vitest';
import { digestText } from './digest.js';
import { activeDays, activity, adoption, retention, type ActiveRow } from './usage.js';

const at = (d: string) => new Date(`${d}T10:00:00Z`);
const row = (userId: string, name: string, d: string): ActiveRow => ({ userId, name, occurredAt: at(d) });

describe('activity', () => {
  const rows = [
    row('a', 'app_opened', '2026-10-20'),
    row('a', 'meal_logged', '2026-10-27'),
    row('b', 'app_opened', '2026-10-27'),
    row('c', 'app_opened', '2026-10-05'),
    row('d', 'day_settled', '2026-10-27'),
  ];
  const result = activity(rows, at('2026-10-27'), 3);

  it('counts people, not events, and ignores scheduled events', () => {
    expect(result.dau).toBe(2);
    expect(result.wau).toBe(2);
    expect(result.mau).toBe(3);
    expect(result.stickiness).toBeCloseTo(2 / 3);
  });

  it('returns one point per day of the range, oldest first', () => {
    expect(result.series.map((p) => p.date)).toEqual(['2026-10-25', '2026-10-26', '2026-10-27']);
    expect(result.series[2]!.activeUsers).toBe(2);
  });
});

describe('retention', () => {
  const signups = [
    { id: 'a', createdAt: at('2026-10-05') }, // Monday
    { id: 'b', createdAt: at('2026-10-06') },
  ];
  const days = activeDays([
    row('a', 'app_opened', '2026-10-06'),
    row('a', 'app_opened', '2026-10-13'),
    row('b', 'app_opened', '2026-10-06'),
  ]);
  const r = retention(signups, days, at('2026-10-20'));

  it('groups sign-ups by week and shows the share back in each later week', () => {
    expect(r.cohorts).toHaveLength(1);
    expect(r.cohorts[0]!.size).toBe(2);
    expect(r.cohorts[0]!.weeks.slice(0, 3)).toEqual([1, 0.5, 0]);
    expect(r.cohorts[0]!.weeks[3]).toBeNull();
  });

  it('works out D1 and D7 only for people old enough', () => {
    expect(r.d1).toEqual({ eligible: 2, returned: 1, rate: 0.5 });
    expect(r.d7.eligible).toBe(2);
    expect(r.d30).toEqual({ eligible: 0, returned: 0, rate: null });
  });
});

describe('adoption', () => {
  it('counts who ever used a feature, used it this week, and used it often', () => {
    const rows = [
      row('a', 'meal_logged', '2026-10-01'),
      row('a', 'meal_logged', '2026-10-02'),
      row('a', 'meal_logged', '2026-10-26'),
      row('b', 'meal_logged', '2026-10-02'),
    ];
    const meals = adoption(rows, at('2026-10-27'), 4).find((f) => f.feature === 'Log a meal')!;
    expect(meals).toMatchObject({ everUsed: 2, usedThisWeek: 1, usedThreeTimes: 1, share: 0.5 });
  });
});

describe('digestText', () => {
  it('shows the change against the previous period', () => {
    const base = { signedUp: 2, activeUsers: 10, mealsLogged: 40, checkInsAnswered: 12, mealFailRate: 0.1, crashes: 0, serverErrors: 1 };
    const text = digestText('daily', base, { ...base, activeUsers: 8, mealsLogged: 0 });
    expect(text).toContain('Active people: 10 (+25%)');
    expect(text).toContain('Meals logged: 40 (+40)');
    expect(text).toContain('Meal log failures: 10%');
  });
});
