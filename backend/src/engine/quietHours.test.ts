import { describe, expect, it } from 'vitest';
import { isWithinQuietHours, localMinutesOfDay } from './quietHours.js';

describe('localMinutesOfDay', () => {
  it('reads wall-clock minutes in the target timezone', () => {
    const t = new Date('2026-01-15T13:37:00Z');
    expect(localMinutesOfDay(t, 'UTC')).toBe(13 * 60 + 37);
    expect(localMinutesOfDay(t, 'America/New_York')).toBe(8 * 60 + 37); // UTC-5 in January
  });

  it('handles midnight without returning 1440', () => {
    const midnightUtc = new Date('2026-06-01T00:00:00Z');
    expect(localMinutesOfDay(midnightUtc, 'UTC')).toBe(0);
  });
});

describe('isWithinQuietHours', () => {
  it('handles a window that wraps midnight (23:00 → 07:00)', () => {
    expect(isWithinQuietHours(23 * 60 + 30, 1380, 420)).toBe(true); // 23:30
    expect(isWithinQuietHours(3 * 60, 1380, 420)).toBe(true); // 03:00
    expect(isWithinQuietHours(10 * 60, 1380, 420)).toBe(false); // 10:00
  });

  it('is start-inclusive and end-exclusive', () => {
    expect(isWithinQuietHours(1380, 1380, 420)).toBe(true);
    expect(isWithinQuietHours(420, 1380, 420)).toBe(false);
  });

  it('handles a same-day window (13:00 → 17:00)', () => {
    expect(isWithinQuietHours(12 * 60, 780, 1020)).toBe(false);
    expect(isWithinQuietHours(15 * 60, 780, 1020)).toBe(true);
    expect(isWithinQuietHours(18 * 60, 780, 1020)).toBe(false);
  });

  it('treats a zero-width window as no quiet hours', () => {
    expect(isWithinQuietHours(0, 600, 600)).toBe(false);
    expect(isWithinQuietHours(600, 600, 600)).toBe(false);
  });
});
