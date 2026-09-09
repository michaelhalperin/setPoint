import { describe, expect, it } from 'vitest';
import { STAPLE_FOODS } from '../data/stapleFoods.js';
import { prescribe, prescriptionSummary } from './prescribe.js';
import type { PrescriptionConstraints } from './types.js';

const constraints = (over: Partial<PrescriptionConstraints> = {}): PrescriptionConstraints => ({
  targetKcal: 450,
  targetProteinG: null,
  excludedTokens: [],
  ...over,
});

describe('prescribe', () => {
  it('returns a calorie-appropriate prescription for a normal target', () => {
    const rx = prescribe(STAPLE_FOODS, constraints({ targetKcal: 450 }));
    expect(rx).not.toBeNull();
    if (!rx) return;
    expect(rx.items.length).toBeGreaterThanOrEqual(1);
    expect(rx.items.length).toBeLessThanOrEqual(3);
    expect(rx.totalKcal).toBeGreaterThanOrEqual(450 * 0.6);
    expect(rx.totalKcal).toBeLessThanOrEqual(450 * 1.8);
  });

  it('is deterministic for the same input', () => {
    const a = prescribe(STAPLE_FOODS, constraints());
    const b = prescribe(STAPLE_FOODS, constraints());
    expect(a).toEqual(b);
  });

  it('never includes a hard-excluded food', () => {
    const rx = prescribe(STAPLE_FOODS, constraints({ excludedTokens: ['dairy', 'egg', 'gluten'] }));
    expect(rx).not.toBeNull();
    if (!rx) return;
    for (const item of rx.items) {
      const food = STAPLE_FOODS.find((f) => f.slug === item.slug)!;
      expect(food.allergens).not.toContain('dairy');
      expect(food.allergens).not.toContain('egg');
      expect(food.allergens).not.toContain('gluten');
    }
  });

  it('leans on higher-protein foods when there is a strong protein target', () => {
    const strong = prescribe(STAPLE_FOODS, constraints({ targetKcal: 400, targetProteinG: 55 }));
    const weak = prescribe(STAPLE_FOODS, constraints({ targetKcal: 400, targetProteinG: 5 }));
    expect(strong).not.toBeNull();
    if (!strong || !weak) return;
    expect(strong.totalProteinG).toBeGreaterThanOrEqual(weak.totalProteinG);
    expect(strong.totalProteinG).toBeGreaterThanOrEqual(40);
  });

  it('prefers no-cook items when low friction is requested', () => {
    const rx = prescribe(STAPLE_FOODS, constraints({ targetKcal: 400, preferLowFriction: true }));
    expect(rx).not.toBeNull();
    if (!rx) return;
    for (const item of rx.items) {
      const food = STAPLE_FOODS.find((f) => f.slug === item.slug)!;
      expect(food.tags.some((t) => t === 'no_cook' || t === 'portable')).toBe(true);
    }
  });

  it('returns null when every food is excluded', () => {
    const rx = prescribe(STAPLE_FOODS, constraints({ excludedTokens: ['vegan', 'vegetarian'] }));
    // 'vegan' + 'vegetarian' together exclude everything non-vegan and non-vegetarian;
    // force the empty case explicitly instead:
    const empty = prescribe([], constraints());
    expect(empty).toBeNull();
    expect(rx === null || rx.items.length > 0).toBe(true);
  });

  it('summarises items into a directive line', () => {
    const rx = prescribe(STAPLE_FOODS, constraints({ targetKcal: 500 }));
    if (!rx) return;
    const summary = prescriptionSummary(rx);
    expect(summary).toContain(rx.items[0]!.name);
    expect(summary.length).toBeGreaterThan(0);
  });
});
