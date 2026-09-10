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
  enforcementEnabled: true,
  paceStatus: 'on_pace',
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
  it('talks about rhythm, never restating the calorie total', async () => {
    const note = await fallbackManagerVoice.homeNote(base);
    expect(note).toBe('Good rhythm so far. Dinner next.');
    expect(note).not.toMatch(/kcal|\\d{3,}/);
  });

  it('names the meal that is running late when behind', async () => {
    const note = await fallbackManagerVoice.homeNote({ ...base, nextMeal: 'lunch', paceStatus: 'behind' });
    expect(note).toBe('Lunch is running late — worth making it a full one.');
  });

  it('frames an empty day by the meal that has to carry it', async () => {
    const note = await fallbackManagerVoice.homeNote({ ...base, mealsToday: 0, nextMeal: 'breakfast', hoursSinceMeal: null });
    expect(note).toBe('A real breakfast now keeps lunch and dinner ordinary.');
  });

  it('keeps going-over calm and never says to fix it urgently', async () => {
    const note = await fallbackManagerVoice.homeNote({ ...base, state: 'over', remainingKcal: -250, mealsToday: 4 });
    expect(note).toBe('A bit past target today. Nothing to fix — steer back tomorrow.');
  });

  it('in quiet mode only describes the day, never prompting', async () => {
    expect(await fallbackManagerVoice.homeNote({ ...base, enforcementEnabled: false })).toBe("Here's today so far.");
    expect(await fallbackManagerVoice.homeNote({ ...base, enforcementEnabled: false, mealsToday: 0 })).toBe(
      'Nothing logged yet today.',
    );
  });

  it('points at the check-in when one is open, without explaining the field', async () => {
    const note = await fallbackManagerVoice.homeNote({ ...base, hasActiveCheckIn: true, mealsToday: 0 });
    expect(note).toMatch(/check-in waiting/i);
    expect(note).not.toMatch(/drop it in|tell me/i);
  });
});
