import { describe, expect, it } from 'vitest';
import {
  pickSuggestedId,
  prescriptionFromSavedMeal,
  serializeSavedMeal,
} from './index.js';

const oats = {
  id: 'sm_oats',
  name: 'Usual oats',
  items: [{ name: 'Oats', quantity: '1 bowl', kcal: 420, proteinG: 18, carbsG: 60, fatG: 10 }],
  kcal: 420,
  proteinG: 18,
  carbsG: 60,
  fatG: 10,
  suggestSlot: 'breakfast' as const,
  useInCheckIns: true,
  lastUsedAt: new Date('2026-09-13T08:00:00Z'),
  useCount: 4,
};

const lunchBox = {
  id: 'sm_lunch',
  name: 'Lunch box',
  items: [{ name: 'Chicken', quantity: '1 box', kcal: 680, proteinG: 45, carbsG: 50, fatG: 22 }],
  kcal: 680,
  proteinG: 45,
  carbsG: 50,
  fatG: 22,
  suggestSlot: 'lunch' as const,
  useInCheckIns: false,
  lastUsedAt: new Date('2026-09-12T12:00:00Z'),
  useCount: 2,
};

describe('pickSuggestedId', () => {
  it('flags the matching slot, preferring the most recently used', () => {
    expect(pickSuggestedId([oats, lunchBox], 'breakfast')).toBe('sm_oats');
    expect(pickSuggestedId([oats, lunchBox], 'lunch')).toBe('sm_lunch');
    expect(pickSuggestedId([oats, lunchBox], 'dinner')).toBeNull();

    const olderOats = { ...oats, id: 'sm_old', lastUsedAt: new Date('2026-01-01T00:00:00Z'), useCount: 99 };
    expect(pickSuggestedId([olderOats, oats], 'breakfast')).toBe('sm_oats');
  });
});

describe('serializeSavedMeal', () => {
  it('marks only the suggested id', () => {
    expect(serializeSavedMeal(oats, 'sm_oats').suggested).toBe(true);
    expect(serializeSavedMeal(lunchBox, 'sm_oats').suggested).toBe(false);
  });
});

describe('prescriptionFromSavedMeal', () => {
  it('snapshots items and keeps the solver target for audit', () => {
    const rx = prescriptionFromSavedMeal(oats, { targetKcal: 700, targetProteinG: 40 });
    expect(rx.totalKcal).toBe(420);
    expect(rx.items[0]).toMatchObject({ name: 'Oats', kcal: 420, unit: '1 bowl' });
    expect(rx.targetKcal).toBe(700);
  });
});
