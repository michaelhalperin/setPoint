import { describe, expect, it } from 'vitest';
import { STAPLE_FOODS } from '../data/stapleFoods.js';
import { isFoodExcluded } from './exclusions.js';
import { ADD_ON_SLUGS, addOnsInText, mealShapeOf, pickTopUp, pickTopUps, topUpHow } from './topUp.js';

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

  it('fits what was just eaten', () => {
    const slugs = (shape: 'bowl' | 'bread' | 'plate' | null) =>
      pickTopUps(foods, { targetKcal: 300, excludedTokens: [], shape }).flatMap((o) => o.items.map((i) => i.slug));
    expect(slugs('plate')).not.toContain('granola');
    expect(slugs('plate')).not.toContain('peanut-butter');
    expect(slugs('bowl')).not.toContain('olive-oil');
    expect(slugs('bowl')).not.toContain('butter');
    // Unknown meal: only things eaten or drunk on the side.
    for (const slug of slugs(null)) expect(['olive-oil', 'butter', 'tahini', 'granola', 'avocado', 'cheddar-cheese', 'peanut-butter', 'almond-butter']).not.toContain(slug);
    // Something goes into a known meal.
    const plate = pickTopUps(foods, { targetKcal: 300, excludedTokens: [], shape: 'plate' });
    expect(plate.some((o) => o.items.some((i) => i.use === 'plate'))).toBe(true);
  });

  it('offers up to three alternatives that share nothing', () => {
    const options = pickTopUps(foods, { targetKcal: 400, excludedTokens: [], shape: 'bowl', seed: 'u1:2026-10-28:breakfast' });
    expect(options.length).toBe(3);
    const slugs = options.flatMap((o) => o.items.map((i) => i.slug));
    expect(new Set(slugs).size).toBe(slugs.length);
    for (const o of options) expect(o.totalKcal).toBeGreaterThanOrEqual(200);
  });

  it('changes from day to day, but not between refreshes', () => {
    const first = (seed: string) =>
      pickTopUp(foods, { targetKcal: 350, excludedTokens: [], shape: 'plate', seed })!.items.map((i) => i.slug).join('+');
    expect(first('u1:2026-10-28:lunch')).toBe(first('u1:2026-10-28:lunch'));
    const days = new Set(Array.from({ length: 10 }, (_, d) => first(`u1:2026-10-${10 + d}:lunch`)));
    expect(days.size).toBeGreaterThan(2);
  });

  it('steers away from recent top-ups and what the meal already had', () => {
    const base = pickTopUp(foods, { targetKcal: 300, excludedTokens: [] })!;
    const used = base.items.map((i) => i.slug);
    const next = pickTopUp(foods, { targetKcal: 300, excludedTokens: [], recentSlugs: used })!;
    expect(next.items.some((i) => used.includes(i.slug))).toBe(false);
    const withMilk = pickTopUps(foods, { targetKcal: 300, excludedTokens: [], mealText: 'cereal with whole milk' });
    expect(withMilk.flatMap((o) => o.items.map((i) => i.slug))).not.toContain('whole-milk');
  });

  it('leans to protein when the day is short on it', () => {
    const rx = pickTopUp(foods, { targetKcal: 200, excludedTokens: [], proteinShortG: 40 })!;
    expect(rx.totalProteinG).toBeGreaterThanOrEqual(20);
  });

  it('skips drinks for someone who said no to drinking calories', () => {
    for (const o of pickTopUps(foods, { targetKcal: 300, excludedTokens: [], drinkableOk: false })) {
      for (const i of o.items) expect(['whole-milk', 'chocolate-milk', 'kefir', 'ready-protein-shake']).not.toContain(i.slug);
    }
  });

  it('says how to eat each add-on', () => {
    for (const shape of ['bowl', 'bread', 'plate', null] as const) {
      for (const o of pickTopUps(foods, { targetKcal: 350, excludedTokens: [], shape })) {
        for (const i of o.items) {
          expect(topUpHow(i.slug, i.use, 'en').length).toBeGreaterThan(0);
          expect(topUpHow(i.slug, i.use, 'he').length).toBeGreaterThan(0);
        }
      }
    }
  });
});

describe('mealShapeOf', () => {
  it('reads the meal from its text', () => {
    expect(mealShapeOf('Oatmeal with banana')).toBe('bowl');
    expect(mealShapeOf('Greek yogurt, granola')).toBe('bowl');
    expect(mealShapeOf('chicken sandwich')).toBe('bread');
    expect(mealShapeOf('Chicken, rice and salad')).toBe('plate');
    expect(mealShapeOf('אורז עם עוף')).toBe('plate');
    expect(mealShapeOf('lunch')).toBeNull();
  });
});

describe('addOnsInText', () => {
  it('finds add-ons in past top-up logs, in either language', () => {
    const slugs = addOnsInText(['Top-up: Whole milk + almonds', 'תוספת: טחינה'], foods, (n) => (n === 'Tahini' ? 'טחינה' : n));
    expect(slugs.sort()).toEqual(['almonds', 'tahini', 'whole-milk']);
  });
});
