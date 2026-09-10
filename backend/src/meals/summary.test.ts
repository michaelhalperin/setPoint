import { describe, expect, it } from 'vitest';
import type { PhotoStore } from '../photos/store.js';
import { toMealSummaries, type MealSummaryRow } from './summary.js';

const row = (over: Partial<MealSummaryRow>): MealSummaryRow => ({
  id: 'm1',
  loggedAt: new Date('2026-09-10T12:00:00Z'),
  kcal: 500,
  proteinG: 30,
  carbsG: 40,
  fatG: 20,
  source: 'PHOTO',
  rawInput: 'Bowl',
  photoUrl: null,
  photoKey: null,
  ...over,
});

const store: PhotoStore = {
  put: async () => 'unused',
  signedUrl: async (key) => {
    if (key.includes('broken')) throw new Error('cannot sign');
    return `https://photos.test/${key}?sig=1`;
  },
  delete: async () => {},
  deleteAllForUser: async () => 0,
};

describe('toMealSummaries', () => {
  it('signs stored photos, keeps legacy inline ones, and drops unsignable ones', async () => {
    const meals = await toMealSummaries(
      [
        row({ id: 'stored', photoKey: 'meals/u1/a.jpg' }),
        row({ id: 'legacy', photoUrl: 'data:image/jpeg;base64,AAAA' }),
        row({ id: 'none', source: 'TEXT' }),
        row({ id: 'broken', photoKey: 'meals/u1/broken.jpg' }),
      ],
      store,
    );

    expect(meals.map((m) => [m.id, m.photoUrl])).toEqual([
      ['stored', 'https://photos.test/meals/u1/a.jpg?sig=1'],
      ['legacy', 'data:image/jpeg;base64,AAAA'],
      ['none', null],
      ['broken', null],
    ]);
  });

  it('omits stored photos when no store is configured', async () => {
    const [meal] = await toMealSummaries([row({ photoKey: 'meals/u1/a.jpg' })], null);
    expect(meal!.photoUrl).toBeNull();
  });
});
