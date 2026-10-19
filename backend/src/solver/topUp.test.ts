import { describe, expect, it } from 'vitest';
import { STAPLE_FOODS } from '../data/stapleFoods.js';
import { isFoodExcluded } from './exclusions.js';
import { ADD_ON_SLUGS, pickTopUp } from './topUp.js';

const foods = STAPLE_FOODS;

describe('pickTopUp', () => {
  it('only uses add-ons that exist in the staple list', () => {
    const slugs = new Set(foods.map((f) => f.slug));
    for (const slug of ADD_ON_SLUGS) expect(slugs.has(slug)).toBe(true);
  });

  it('lands near the ask with one or two add-ons', () => {
    const rx = pickTopUp(foods, { targetKcal: 350, excludedTokens: [] })!;
    expect(rx.items.length).toBeGreaterThanOrEqual(1);
    expect(rx.items.length).toBeLessThanOrEqual(2);
    expect(rx.totalKcal).toBeGreaterThanOrEqual(300);
    expect(rx.totalKcal).toBeLessThanOrEqual(450);
  });

  it('is deterministic', () => {
    const a = pickTopUp(foods, { targetKcal: 420, excludedTokens: ['dairy'] });
    const b = pickTopUp(foods, { targetKcal: 420, excludedTokens: ['dairy'] });
    expect(a).toEqual(b);
  });

  it('never suggests a restricted add-on', () => {
    for (const tokens of [['dairy'], ['peanut', 'tree_nut'], ['vegan'], ['dairy', 'peanut', 'tree_nut', 'sesame']]) {
      for (const targetKcal of [150, 300, 500]) {
        const rx = pickTopUp(foods, { targetKcal, excludedTokens: tokens });
        for (const item of rx?.items ?? []) {
          const food = foods.find((f) => f.slug === item.slug)!;
          expect(isFoodExcluded(food, tokens)).toBe(false);
        }
      }
    }
  });

  it('returns null when nothing is allowed', () => {
    const allowedNone = ADD_ON_SLUGS.map((s) => s.replace(/-/g, ' '));
    expect(pickTopUp(foods, { targetKcal: 300, excludedTokens: ['dairy', 'peanut', 'tree_nut', 'sesame', ...allowedNone] })).toBeNull();
  });
});
