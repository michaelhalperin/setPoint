import { describe, expect, it } from 'vitest';
import { fallbackManagerVoice, mealWindow } from './fallback.js';
import type { HomeNoteContext } from './types.js';

const base: HomeNoteContext = {
  goal: 'BULK',
  state: 'under',
  consumedKcal: 1240,
  targetKcal: 3100,
  remainingKcal: 1860,
  remainingProteinG: 93,
  mealsToday: 2,
  nextMeal: 'dinner',
  hoursSinceMeal: 2,
  hasActiveCheckIn: false,
};

describe('mealWindow', () => {
  const times = { lunchMin: 780, dinnerMin: 1140 };
  it('splits at lunch and dinner, not midpoints', () => {
    expect(mealWindow(479, times)).toBe('breakfast');
    expect(mealWindow(780, times)).toBe('lunch');
    expect(mealWindow(1140, times)).toBe('dinner');
  });
});

describe('fallback homeNote', () => {
  it('sizes the next meal instead of pointing at the field', async () => {
    const note = await fallbackManagerVoice.homeNote(base);
    expect(note).toBe('1860 kcal · 93 g protein left.');
  });

  it('names breakfast when the day is empty', async () => {
    const note = await fallbackManagerVoice.homeNote({
      ...base,
      consumedKcal: 0,
      remainingKcal: 3100,
      remainingProteinG: 165,
      mealsToday: 0,
      nextMeal: 'breakfast',
      hoursSinceMeal: null,
    });
    expect(note).toMatch(/breakfast: ~1,?050 kcal/i);
  });

  it('keeps the original over-target line', async () => {
    const note = await fallbackManagerVoice.homeNote({
      ...base,
      state: 'over',
      remainingKcal: -250,
      remainingProteinG: 10,
      mealsToday: 4,
    });
    expect(note).toBe('Over target. Continue tomorrow.');
  });

  it('points at the check-in when one is open', async () => {
    const note = await fallbackManagerVoice.homeNote({ ...base, hasActiveCheckIn: true, mealsToday: 0 });
    expect(note).toMatch(/check-in/i);
    expect(note).not.toMatch(/drop it in|tell me/i);
  });
});
