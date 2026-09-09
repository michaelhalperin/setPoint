import { describe, expect, it } from 'vitest';
import { STAPLE_FOODS } from '../data/stapleFoods.js';
import { filterAllowedFoods, isFoodExcluded } from './exclusions.js';
import type { SolverFood } from './types.js';

const bySlug = (slug: string): SolverFood => {
  const f = STAPLE_FOODS.find((x) => x.slug === slug);
  if (!f) throw new Error(`no food ${slug}`);
  return f;
};

describe('isFoodExcluded', () => {
  it('excludes any food carrying a named allergen', () => {
    expect(isFoodExcluded(bySlug('peanut-butter'), ['peanut'])).toBe(true);
    expect(isFoodExcluded(bySlug('mixed-nuts'), ['peanut'])).toBe(true); // peanut in allergens
    expect(isFoodExcluded(bySlug('pb-banana-toast'), ['peanut'])).toBe(true);
    expect(isFoodExcluded(bySlug('greek-yogurt-plain'), ['peanut'])).toBe(false);
  });

  it('handles multi-word allergen tokens like "tree nut"', () => {
    expect(isFoodExcluded(bySlug('almonds'), ['tree nut'])).toBe(true);
    expect(isFoodExcluded(bySlug('almonds'), ['tree_nut'])).toBe(true);
  });

  it('enforces vegetarian and vegan as hard diets', () => {
    expect(isFoodExcluded(bySlug('chicken-breast'), ['vegetarian'])).toBe(true);
    expect(isFoodExcluded(bySlug('canned-tuna'), ['vegetarian'])).toBe(true);
    expect(isFoodExcluded(bySlug('greek-yogurt-plain'), ['vegetarian'])).toBe(false);
    expect(isFoodExcluded(bySlug('greek-yogurt-plain'), ['vegan'])).toBe(true); // dairy
    expect(isFoodExcluded(bySlug('black-beans'), ['vegan'])).toBe(false);
  });

  it('matches a plain restriction against the food name', () => {
    expect(isFoodExcluded(bySlug('ground-beef-90'), ['beef'])).toBe(true);
    expect(isFoodExcluded(bySlug('chicken-breast'), ['beef'])).toBe(false);
  });

  it('ignores blank tokens', () => {
    expect(isFoodExcluded(bySlug('banana'), ['', '   '])).toBe(false);
  });
});

describe('filterAllowedFoods', () => {
  it('drops every excluded food and keeps the rest', () => {
    const allowed = filterAllowedFoods(STAPLE_FOODS, ['dairy', 'fish']);
    expect(allowed.some((f) => f.allergens.includes('dairy'))).toBe(false);
    expect(allowed.some((f) => f.allergens.includes('fish'))).toBe(false);
    expect(allowed.some((f) => f.slug === 'banana')).toBe(true);
  });
});
