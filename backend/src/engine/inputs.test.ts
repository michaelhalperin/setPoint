import { describe, expect, it } from 'vitest';
import { ENGINE_CONFIG } from './config.js';
import { deriveHoursSinceLastLog, deriveHoursSinceMeal, isBiosignalFresh } from './inputs.js';

const NOW = new Date('2026-05-01T12:00:00Z');
const hoursAgo = (h: number) => new Date(NOW.getTime() - h * 3_600_000);

describe('deriveHoursSinceMeal', () => {
  it('measures from the last meal when there is one', () => {
    expect(deriveHoursSinceMeal(hoursAgo(4), hoursAgo(100), NOW)).toBeCloseTo(4, 5);
  });

  it('falls back to capped account age when no meal was ever logged', () => {
    expect(deriveHoursSinceMeal(null, hoursAgo(3), NOW)).toBeCloseTo(3, 5);
    expect(deriveHoursSinceMeal(null, hoursAgo(1000), NOW)).toBe(ENGINE_CONFIG.noMealFallbackHours);
  });

  it('never returns a negative value', () => {
    expect(deriveHoursSinceMeal(new Date(NOW.getTime() + 3_600_000), hoursAgo(10), NOW)).toBe(0);
  });
});

describe('deriveHoursSinceLastLog', () => {
  it('uses the last log, or account creation as a floor', () => {
    expect(deriveHoursSinceLastLog(hoursAgo(2), hoursAgo(50), NOW)).toBeCloseTo(2, 5);
    expect(deriveHoursSinceLastLog(null, hoursAgo(6), NOW)).toBeCloseTo(6, 5);
  });
});

describe('isBiosignalFresh', () => {
  it('accepts recent readings and rejects stale ones', () => {
    expect(isBiosignalFresh(hoursAgo(ENGINE_CONFIG.biosignalMaxAgeHours - 1), NOW)).toBe(true);
    expect(isBiosignalFresh(hoursAgo(ENGINE_CONFIG.biosignalMaxAgeHours + 1), NOW)).toBe(false);
  });
});
