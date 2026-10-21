import { describe, expect, it } from 'vitest';
import { STAPLE_FOODS } from '../data/stapleFoods.js';
import { prescribe } from './prescribe.js';
import type { PrescriptionConstraints } from './types.js';

/**
 * Phase 0 miss-rate gate for the nutrition-assistant aha chips.
 * Thresholds (plan v4): no-cook miss ≤ 20% of profiles; drinkable miss ≤ 40%.
 * drinkableOk false is a user preference (honest miss on the drink chip), not a
 * food-filter profile, so it is not in this matrix.
 */
const TARGET_KCAL = 300;

type Profile = { name: string; excludedTokens: string[] };

const PROFILES: Profile[] = [
  { name: 'none', excludedTokens: [] },
  { name: 'dairy-free', excludedTokens: ['dairy'] },
  { name: 'vegan', excludedTokens: ['vegan'] },
  { name: 'soy-free', excludedTokens: ['soy'] },
  { name: 'gluten-free', excludedTokens: ['gluten'] },
  { name: 'nut-free', excludedTokens: ['peanut', 'tree_nut'] },
  { name: 'dairy-free+soy-free', excludedTokens: ['dairy', 'soy'] },
  { name: 'vegan+soy-free', excludedTokens: ['vegan', 'soy'] },
  { name: 'vegan+gluten-free', excludedTokens: ['vegan', 'gluten'] },
  { name: 'bulk-typical', excludedTokens: [] },
  { name: 'maintain-typical', excludedTokens: [] },
  { name: 'egg-free', excludedTokens: ['egg'] },
];

function plate(over: Partial<PrescriptionConstraints>) {
  return prescribe(STAPLE_FOODS, {
    targetKcal: TARGET_KCAL,
    targetProteinG: 25,
    excludedTokens: [],
    ...over,
  });
}

describe('nutrition aha miss-rate matrix', () => {
  it('keeps no-cook and drinkable misses under the Phase 0 thresholds', () => {
    const noCookMisses: string[] = [];
    const drinkMisses: string[] = [];

    for (const profile of PROFILES) {
      const noCook = plate({ requireNoCook: true, excludedTokens: profile.excludedTokens });
      if (!noCook) noCookMisses.push(profile.name);
      const drink = plate({ requireDrinkable: true, excludedTokens: profile.excludedTokens });
      if (!drink) drinkMisses.push(profile.name);
    }

    const noCookRate = noCookMisses.length / PROFILES.length;
    const drinkRate = drinkMisses.length / PROFILES.length;

    expect(noCookRate, `no-cook misses (${noCookMisses.join(', ') || 'none'})`).toBeLessThanOrEqual(0.2);
    expect(drinkRate, `drinkable misses (${drinkMisses.join(', ') || 'none'})`).toBeLessThanOrEqual(0.4);
  });
});
