import { describe, expect, it } from 'vitest';
import { buildGapMetrics } from './gapMetrics.js';

describe('buildGapMetrics', () => {
  it('counts a day as closed at 95% of target and averages the shortfall of the rest', () => {
    const m = buildGapMetrics(
      [
        { kcalConsumed: 2900, kcalTarget: 3000 },
        { kcalConsumed: 3100, kcalTarget: 3000 },
        { kcalConsumed: 2400, kcalTarget: 3000 },
        { kcalConsumed: 2000, kcalTarget: 3000 },
        { kcalConsumed: 0, kcalTarget: 0 },
      ],
      [],
    );
    expect(m.days).toEqual({ total: 4, closed: 2, gapClosedRate: 0.5, avgShortfallKcal: 800 });
  });

  it('reports how each kind of check-in ended', () => {
    const m = buildGapMetrics([], [
      { kind: 'CLOSE', status: 'LOGGED' },
      { kind: 'CLOSE', status: 'EXPIRED' },
      { kind: 'TOP_UP', status: 'LOGGED' },
    ]);
    expect(m.byKind).toEqual({
      CLOSE: { total: 2, logged: 1, loggedRate: 0.5 },
      TOP_UP: { total: 1, logged: 1, loggedRate: 1 },
    });
    expect(m.days.avgShortfallKcal).toBeNull();
  });
});
