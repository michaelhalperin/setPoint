import { describe, expect, it } from 'vitest';
import type { SolverFood } from '../solver/index.js';
import { alternativesFor, swapQuantity } from './swap.js';

const food = (slug: string, kcal: number, extra: Partial<SolverFood> = {}): SolverFood => ({
  slug,
  name: slug,
  servingDesc: '1 serving',
  kcal,
  proteinG: 10,
  carbsG: 10,
  fatG: 5,
  tags: [],
  allergens: [],
  ...extra,
});

const foods = [
  food('chocolate-milk', 210),
  food('whole-milk', 150),
  food('kefir', 110),
  food('banana', 100),
  food('rice', 200),
  food('peanut-butter', 190, { allergens: ['peanuts'] }),
];

describe('swapQuantity', () => {
  it('rounds to half servings and stays sane', () => {
    expect(swapQuantity(210, { kcal: 150 })).toBe(1.5);
    expect(swapQuantity(10, { kcal: 300 })).toBe(0.5);
    expect(swapQuantity(2000, { kcal: 100 })).toBe(3);
  });
});

describe('alternativesFor', () => {
  it('swaps a drink for drinks, closest calories first, and not what is already on the plate', () => {
    const out = alternativesFor({ foods, excludedTokens: [], current: { slug: 'chocolate-milk', kcal: 210 }, onPlate: ['chocolate-milk', 'whole-milk'] });
    expect(out.map((a) => a.slug)).toEqual(['kefir']);
  });

  it('swaps food for food and leaves out what the person avoids', () => {
    const out = alternativesFor({ foods, excludedTokens: ['peanuts'], current: { slug: 'banana', kcal: 100 }, onPlate: ['banana'] });
    expect(out.map((a) => a.slug)).toEqual(['rice']);
    expect(out[0]).toMatchObject({ quantity: 0.5, kcal: 100, deltaKcal: 0 });
  });
});
