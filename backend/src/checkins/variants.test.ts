import { describe, expect, it } from 'vitest';
import { STAPLE_FOODS } from '../data/stapleFoods.js';
import {
  publicPrescription,
  solveCheckInVariant,
  variantSolverPrefs,
} from './variants.js';

const foodIdBySlug = new Map(STAPLE_FOODS.map((f) => [f.slug, `id-${f.slug}`]));

const base = {
  foods: STAPLE_FOODS,
  foodIdBySlug,
  targetKcal: 670,
  targetProteinG: 40,
  excludedTokens: [] as string[],
  pantryTokens: [] as string[],
  prepTimeMaxMin: null as number | null,
  drinkableOk: true,
};

describe('check-in variants', () => {
  it('turns on dense/drinkable prefs only for the smaller plate', () => {
    expect(variantSolverPrefs('full', true)).toEqual({
      preferLowFriction: false,
      preferCalorieDense: false,
      preferDrinkable: false,
    });
    expect(variantSolverPrefs('smaller', true)).toEqual({
      preferLowFriction: true,
      preferCalorieDense: true,
      preferDrinkable: true,
    });
    expect(variantSolverPrefs('smaller', false).preferDrinkable).toBe(false);
  });

  it('builds full and smaller plates at the same target, honouring exclusions', () => {
    const excluded = ['dairy', 'egg', 'gluten'];
    const full = solveCheckInVariant({ ...base, excludedTokens: excluded, variant: 'full' });
    const smaller = solveCheckInVariant({ ...base, excludedTokens: excluded, variant: 'smaller' });
    expect(full).not.toBeNull();
    expect(smaller).not.toBeNull();
    if (!full || !smaller) return;

    expect(full.totals.kcal).toBeGreaterThan(0);
    expect(smaller.totals.kcal).toBeGreaterThan(0);
    // Same target — totals land in the same band.
    expect(Math.abs(full.totals.kcal - smaller.totals.kcal)).toBeLessThan(full.totals.kcal * 0.5);

    for (const plate of [full, smaller]) {
      for (const item of plate.items) {
        const food = STAPLE_FOODS.find((f) => f.name === item.name);
        expect(food).toBeDefined();
        expect(food!.allergens).not.toContain('dairy');
        expect(food!.allergens).not.toContain('egg');
        expect(food!.allergens).not.toContain('gluten');
      }
    }

    const pub = publicPrescription(smaller, 'rx_1');
    expect(pub.id).toBe('rx_1');
    expect(pub.items[0]?.name).toBeTruthy();
  });
});
