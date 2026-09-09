import { describe, expect, it } from 'vitest';
import { expectedGapHours } from './expectedGap.js';

describe('expectedGapHours', () => {
  it('averages the two daytime gaps for standard meal times', () => {
    // 08:00 / 13:00 / 19:00 → gaps 5h and 6h → mean 5.5h
    expect(expectedGapHours({ breakfastMin: 480, lunchMin: 780, dinnerMin: 1140 })).toBeCloseTo(5.5, 5);
  });

  it('handles a night-shift schedule that wraps past midnight', () => {
    // "breakfast" 20:00, "lunch" 03:00, "dinner" 10:00 → gaps 7h and 7h
    expect(expectedGapHours({ breakfastMin: 1200, lunchMin: 180, dinnerMin: 600 })).toBeCloseTo(7, 5);
  });

  it('clamps implausibly short schedules up to the minimum', () => {
    // all meals within an hour → tiny gaps
    expect(expectedGapHours({ breakfastMin: 480, lunchMin: 500, dinnerMin: 520 })).toBe(3);
  });

  it('clamps implausibly long schedules down to the maximum', () => {
    expect(expectedGapHours({ breakfastMin: 60, lunchMin: 720, dinnerMin: 1380 })).toBe(10);
  });

  it('falls back to a default for degenerate identical times', () => {
    expect(expectedGapHours({ breakfastMin: 600, lunchMin: 600, dinnerMin: 600 })).toBeGreaterThanOrEqual(3);
  });
});
