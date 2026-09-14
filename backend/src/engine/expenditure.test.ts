import { describe, expect, it } from 'vitest';
import {
  EXPENDITURE_WINDOW_DAYS,
  estimateExpenditure,
  weeklyIntakeBars,
} from './expenditure.js';

function days(kcal: number[], start = '2026-07-20'): { date: string; kcal: number }[] {
  const t0 = Date.parse(`${start}T00:00:00Z`);
  return kcal.map((n, i) => {
    const iso = new Date(t0 + i * 86_400_000).toISOString().slice(0, 10);
    return { date: iso, kcal: n };
  });
}

function weighIns(points: { day: number; kg: number }[], start = '2026-07-20'): { at: Date; kg: number }[] {
  const t0 = Date.parse(`${start}T12:00:00Z`);
  return points.map((p) => ({ at: new Date(t0 + p.day * 86_400_000), kg: p.kg }));
}

const full = Array.from({ length: EXPENDITURE_WINDOW_DAYS }, () => 2800);
const sixWeighIns = weighIns([
  { day: 0, kg: 80 },
  { day: 10, kg: 80 },
  { day: 20, kg: 80 },
  { day: 30, kg: 80 },
  { day: 40, kg: 80 },
  { day: 55, kg: 80 },
]);

describe('expenditure.v1', () => {
  it('matches average intake when weight is flat', () => {
    const est = estimateExpenditure({ days: days(full), weighIns: sixWeighIns });
    expect(est.ready).toBe(true);
    expect(est.burnKcal).toBe(2800);
    expect(est.rangeLow).toBeLessThanOrEqual(est.burnKcal!);
    expect(est.rangeHigh).toBeGreaterThanOrEqual(est.burnKcal!);
  });

  it('subtracts stored energy when weight is rising', () => {
    const rising = weighIns([
      { day: 0, kg: 80 },
      { day: 11, kg: 80.2 },
      { day: 22, kg: 80.4 },
      { day: 33, kg: 80.6 },
      { day: 44, kg: 80.8 },
      { day: 55, kg: 81 },
    ]);
    const est = estimateExpenditure({ days: days(full), weighIns: rising });
    expect(est.ready).toBe(true);
    expect(est.burnKcal!).toBeLessThan(2800);
    expect(est.burnKcal!).toBeGreaterThan(2500);
  });

  it('adds released energy when weight is falling', () => {
    const falling = weighIns([
      { day: 0, kg: 81 },
      { day: 11, kg: 80.8 },
      { day: 22, kg: 80.6 },
      { day: 33, kg: 80.4 },
      { day: 44, kg: 80.2 },
      { day: 55, kg: 80 },
    ]);
    const est = estimateExpenditure({ days: days(full), weighIns: falling });
    expect(est.ready).toBe(true);
    expect(est.burnKcal!).toBeGreaterThan(2800);
  });

  it('needs 28 logged days, 80% coverage, and 6 weigh-ins', () => {
    expect(estimateExpenditure({ days: days(full.slice(0, 20)), weighIns: sixWeighIns }).reason).toBe(
      'not_enough_days',
    );
    const sparse = days(Array.from({ length: 56 }, (_, i) => (i % 2 === 0 ? 2800 : 0)));
    expect(estimateExpenditure({ days: sparse, weighIns: sixWeighIns }).reason).toBe('not_enough_logs');
    expect(estimateExpenditure({ days: days(full), weighIns: sixWeighIns.slice(0, 5) }).reason).toBe(
      'not_enough_weighins',
    );
  });

  it('builds weekly intake bars with a burn band', () => {
    const est = estimateExpenditure({ days: days(full), weighIns: sixWeighIns });
    const weeks = weeklyIntakeBars(days(full), {
      burnKcal: est.burnKcal!,
      rangeLow: est.rangeLow!,
      rangeHigh: est.rangeHigh!,
    });
    expect(weeks).toHaveLength(8);
    expect(weeks[0]?.intakeKcal).toBe(2800);
    expect(weeks[0]?.burnKcal).toBe(2800);
  });
});
