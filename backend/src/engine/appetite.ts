import { MIN_DAILY_KCAL } from '../onboarding/targets.js';
import type { MealTimes } from './mealSchedule.js';

export const APPETITE_VERSION = 'appetite.v1';

export type AppetiteMode = 'NORMAL' | 'SMALL_FREQUENT';
export type AppetiteLevel = 'HUNGRY' | 'NORMAL' | 'LOW';
export type AppetiteShape = 'HUNGRY' | 'NORMAL' | 'SMALL';

export const CALORIE_DENSE_SLUGS = new Set([
  'whole-milk',
  'peanut-butter',
  'granola',
  'olive-oil',
  'medjool-dates',
  'cheddar-cheese',
  'almonds',
  'trail-mix',
  'avocado',
  'greek-yogurt-granola',
]);

export const DRINKABLE_SLUGS = new Set([
  'whole-milk',
  'kefir',
  'whey-protein-shake',
  'ready-protein-shake',
  'plant-protein-shake',
]);

export function appetiteShape(mode: AppetiteMode, dayLevel: AppetiteLevel | null): AppetiteShape {
  if (dayLevel === 'HUNGRY') return 'HUNGRY';
  if (dayLevel === 'LOW' || mode === 'SMALL_FREQUENT') return 'SMALL';
  return 'NORMAL';
}

export type ExtraSlot = { slot: 'snack_am' | 'snack_pm'; mealMin: number };

export function extraAppetiteSlots(times: MealTimes): ExtraSlot[] {
  return [
    { slot: 'snack_am', mealMin: Math.floor((times.breakfastMin + times.lunchMin) / 2) },
    { slot: 'snack_pm', mealMin: Math.floor((times.lunchMin + times.dinnerMin) / 2) },
  ];
}

export function remainingSlotCount(input: {
  nowMin: number;
  times: MealTimes;
  extra: boolean;
  checked: string[];
  mealMinutesToday: number[];
}): number {
  const slots = input.extra
    ? [
        { slot: 'breakfast', mealMin: input.times.breakfastMin },
        ...extraAppetiteSlots(input.times),
        { slot: 'lunch', mealMin: input.times.lunchMin },
        { slot: 'dinner', mealMin: input.times.dinnerMin },
      ]
    : [
        { slot: 'breakfast', mealMin: input.times.breakfastMin },
        { slot: 'lunch', mealMin: input.times.lunchMin },
        { slot: 'dinner', mealMin: input.times.dinnerMin },
      ];
  return slots.filter((s) => s.mealMin + 45 > input.nowMin && !input.checked.includes(s.slot)).length || 1;
}

/** Same daily total, split across the remaining slots. Never below the safety floor for a day. */
export function appetiteMealTarget(input: {
  remainingKcal: number;
  remainingSlots: number;
  shape: AppetiteShape;
}): number {
  const remaining = Math.max(0, input.remainingKcal);
  if (input.shape === 'NORMAL') return remaining;
  const split = remaining / Math.max(1, input.remainingSlots);
  if (input.shape === 'SMALL') return Math.min(450, Math.max(200, Math.round(split / 10) * 10));
  return Math.min(900, Math.max(400, Math.round(split / 10) * 10));
}

export function dayStaysAboveFloor(dailyTarget: number): number {
  return Math.max(MIN_DAILY_KCAL, dailyTarget);
}
