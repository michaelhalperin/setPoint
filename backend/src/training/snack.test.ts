import { describe, expect, it } from 'vitest';
import { mealName, pickSnackBefore } from './snack.js';

const at = (iso: string) => new Date(iso);
const yogurt = {
  loggedAt: at('2026-10-14T15:40:00Z'),
  kcal: 220,
  items: [{ name: 'Greek yogurt', quantity: '1 cup', kcal: 220, proteinG: 20, carbsG: 12, fatG: 5 }],
};
const banana = {
  loggedAt: at('2026-10-10T10:00:00Z'),
  kcal: 180,
  items: [{ name: 'Banana', quantity: '1', kcal: 105, proteinG: 1, carbsG: 27, fatG: 0 }, { name: 'Peanut butter', quantity: '1 tbsp', kcal: 75, proteinG: 3, carbsG: 3, fatG: 6 }],
};
const dinner = {
  loggedAt: at('2026-10-14T19:30:00Z'),
  kcal: 820,
  items: [{ name: 'Chicken plate', quantity: '1', kcal: 820, proteinG: 50, carbsG: 70, fatG: 22 }],
};

describe('pickSnackBefore', () => {
  it('names a logged snack from its items', () => {
    expect(mealName(yogurt)).toBe('Greek yogurt');
    expect(mealName(banana)).toBe('Banana + Peanut butter');
  });

  it('prefers a snack they ate before a session', () => {
    const pick = pickSnackBefore({
      meals: [yogurt, dinner],
      workouts: [{ start: at('2026-10-14T17:00:00Z') }],
      savedMeals: [{ name: 'Overnight oats', kcal: 310, useCount: 8, lastUsedAt: at('2026-10-12T08:00:00Z'), useInCheckIns: true }],
    });
    expect(pick).toMatchObject({ name: 'Greek yogurt', kcal: 220, source: 'history' });
  });

  it('prefers a logged snack over a saved plate even without a session', () => {
    const pick = pickSnackBefore({
      meals: [yogurt],
      workouts: [],
      savedMeals: [{ name: 'Overnight oats', kcal: 310, useCount: 8, lastUsedAt: at('2026-10-12T08:00:00Z'), useInCheckIns: true }],
    });
    expect(pick).toMatchObject({ name: 'Greek yogurt', kcal: 220, source: 'history' });
    expect(pick?.items?.[0]).toMatchObject({ name: 'Greek yogurt', quantity: '1 cup', kcal: 220 });
  });

  it('uses a usual plate when they have no pre-session snack', () => {
    const pick = pickSnackBefore({
      meals: [dinner],
      workouts: [{ start: at('2026-10-14T17:00:00Z') }],
      savedMeals: [{ name: 'Overnight oats', kcal: 310, useCount: 8, lastUsedAt: at('2026-10-12T08:00:00Z'), useInCheckIns: true }],
    });
    expect(pick).toMatchObject({ name: 'Overnight oats', kcal: 310, source: 'usual' });
  });

  it('skips foods they dislike', () => {
    const pick = pickSnackBefore({
      meals: [yogurt],
      workouts: [{ start: at('2026-10-14T17:00:00Z') }],
      savedMeals: [],
      dislikedFoods: ['yogurt'],
    });
    expect(pick).toBeNull();
  });

  it('falls back to a light staple that fits their foods', () => {
    const pick = pickSnackBefore({
      meals: [],
      workouts: [],
      savedMeals: [],
      solverFoods: [
        {
          slug: 'chocolate_milk',
          name: 'Chocolate milk',
          servingDesc: '1 cup',
          kcal: 220,
          proteinG: 8,
          carbsG: 26,
          fatG: 8,
          tags: ['no_cook', 'portable', 'vegetarian'],
          allergens: ['dairy'],
        },
      ],
    });
    expect(pick?.source).toBe('suggested');
    expect(pick?.name.toLowerCase()).toContain('chocolate milk');
  });
});
