import { describe, expect, it } from 'vitest';
import {
  appetiteMealTarget,
  appetiteShape,
  extraAppetiteSlots,
  nextAppetitePlate,
  remainingSlotCount,
} from './appetite.js';

const times = { breakfastMin: 480, lunchMin: 780, dinnerMin: 1140 };

describe('appetite.v1', () => {
  it('treats SMALL_FREQUENT and LOW as extra slots, HUNGRY as larger bites', () => {
    expect(appetiteShape('NORMAL', null)).toBe('NORMAL');
    expect(appetiteShape('SMALL_FREQUENT', null)).toBe('SMALL');
    expect(appetiteShape('NORMAL', 'LOW')).toBe('SMALL');
    expect(appetiteShape('SMALL_FREQUENT', 'HUNGRY')).toBe('HUNGRY');
  });

  it('places extra slots at the midpoints', () => {
    expect(extraAppetiteSlots(times)).toEqual([
      { slot: 'snack_am', mealMin: 630 },
      { slot: 'snack_pm', mealMin: 960 },
    ]);
  });

  it('splits the same daily remainder across more slots when small', () => {
    const remaining = 1800;
    const small = appetiteMealTarget({ remainingKcal: remaining, remainingSlots: 4, shape: 'SMALL' });
    const hungry = appetiteMealTarget({ remainingKcal: remaining, remainingSlots: 2, shape: 'HUNGRY' });
    expect(small).toBe(450);
    expect(hungry).toBe(900);
    expect(small * 4).toBeLessThanOrEqual(remaining);
  });

  it('counts remaining slots including extra ones', () => {
    expect(
      remainingSlotCount({
        nowMin: 500,
        times,
        extra: true,
        checked: ['breakfast'],
        mealMinutesToday: [490],
      }),
    ).toBe(4);
  });

  it('names the next plate and its suggested kcal', () => {
    expect(
      nextAppetitePlate({
        nowMin: 400,
        times,
        shape: 'SMALL',
        remainingKcal: 3100,
        checked: [],
        mealMinutesToday: [],
      }),
    ).toEqual({ slot: 'breakfast', atMin: 480, kcal: 450 });

    expect(
      nextAppetitePlate({
        nowMin: 700,
        times,
        shape: 'NORMAL',
        remainingKcal: 1800,
        checked: ['breakfast'],
        mealMinutesToday: [490],
      }),
    ).toEqual({ slot: 'lunch', atMin: 780, kcal: 1800 });

    expect(
      nextAppetitePlate({
        nowMin: 1300,
        times,
        shape: 'NORMAL',
        remainingKcal: 400,
        checked: ['breakfast', 'lunch', 'dinner'],
        mealMinutesToday: [490, 800, 1150],
      }),
    ).toBeNull();
  });
});
