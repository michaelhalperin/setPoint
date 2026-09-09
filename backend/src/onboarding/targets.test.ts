import { describe, expect, it } from 'vitest';
import {
  ageFromBirthDate,
  clampPaceKgPerWeek,
  computeCalorieTarget,
  computeProteinTarget,
  mifflinStJeorRmr,
  paceToKcalDelta,
  type BodyStats,
} from './targets.js';

const stats: BodyStats = {
  sex: 'MALE',
  weightKg: 80,
  heightCm: 180,
  ageYears: 30,
  activityLevel: 'MODERATE',
};

describe('mifflinStJeorRmr', () => {
  it('matches the textbook formula for a male', () => {
    // 10*80 + 6.25*180 - 5*30 + 5 = 800 + 1125 - 150 + 5 = 1780
    expect(mifflinStJeorRmr(stats)).toBe(1780);
  });

  it('applies the female and unspecified offsets', () => {
    expect(mifflinStJeorRmr({ ...stats, sex: 'FEMALE' })).toBe(1780 - 5 - 161);
    expect(mifflinStJeorRmr({ ...stats, sex: 'UNSPECIFIED' })).toBe(1780 - 5 - 78);
  });
});

describe('computeCalorieTarget', () => {
  it('adds a surplus for a bulk and a deficit for a diet', () => {
    const bulk = computeCalorieTarget(stats, 'BULK');
    const diet = computeCalorieTarget(stats, 'DIET');
    expect(bulk).toBeGreaterThan(diet);
    // TDEE ≈ 1780 * 1.55 = 2759; bulk ≈ +350, diet ≈ -400
    expect(bulk).toBeGreaterThan(3000);
    expect(diet).toBeLessThan(2400);
    expect(bulk % 10).toBe(0);
  });

  it('never returns below the 1200 floor', () => {
    const tiny: BodyStats = { sex: 'FEMALE', weightKg: 40, heightCm: 150, ageYears: 70, activityLevel: 'SEDENTARY' };
    expect(computeCalorieTarget(tiny, 'DIET')).toBeGreaterThanOrEqual(1200);
  });
});

describe('computeProteinTarget', () => {
  it('is higher per kg on a diet than a bulk, lower for maintenance', () => {
    expect(computeProteinTarget(80, 'DIET')).toBe(160);
    expect(computeProteinTarget(80, 'BULK')).toBe(144);
    expect(computeProteinTarget(80, 'MAINTAIN')).toBe(128);
  });
});

describe('pace (M16)', () => {
  it('paceToKcalDelta is a signed daily delta, zero for maintenance', () => {
    expect(paceToKcalDelta('DIET', 0.5)).toBe(-Math.round((0.5 * 7700) / 7)); // -550
    expect(paceToKcalDelta('BULK', 0.25)).toBe(Math.round((0.25 * 7700) / 7)); // +275
    expect(paceToKcalDelta('MAINTAIN', 1)).toBe(0);
  });

  it('clampPaceKgPerWeek caps a diet at 0.75%/wk of bodyweight and a bulk at 0.5', () => {
    expect(clampPaceKgPerWeek('DIET', 80, 5)).toBeCloseTo(0.6); // 80 * 0.0075
    expect(clampPaceKgPerWeek('BULK', 80, 5)).toBe(0.5);
    expect(clampPaceKgPerWeek('DIET', 80, 0)).toBe(0.1); // floored, never zero for a real goal
    expect(clampPaceKgPerWeek('MAINTAIN', 80, 0.5)).toBe(0);
  });

  it('computeCalorieTarget derives the deficit from pace when given', () => {
    const flat = computeCalorieTarget(stats, 'DIET');
    const gentle = computeCalorieTarget(stats, 'DIET', { paceKgPerWeek: 0.25 });
    expect(gentle).toBeGreaterThan(flat); // smaller deficit than the -400 fallback
  });
});

describe('ageFromBirthDate', () => {
  it('accounts for whether the birthday has passed', () => {
    expect(ageFromBirthDate(new Date('1990-01-01'), new Date('2026-06-01'))).toBe(36);
    expect(ageFromBirthDate(new Date('1990-12-31'), new Date('2026-06-01'))).toBe(35);
  });
});
