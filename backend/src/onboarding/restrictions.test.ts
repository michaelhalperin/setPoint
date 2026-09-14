import { describe, expect, it } from 'vitest';
import { mergeRestrictions, parseRestrictionFreeText } from './restrictions.js';
import { isFoodExcluded } from '../solver/exclusions.js';
import { STAPLE_FOODS } from '../data/stapleFoods.js';

const bySlug = (slug: string) => {
  const f = STAPLE_FOODS.find((x) => x.slug === slug);
  if (!f) throw new Error(`no food ${slug}`);
  return f;
};

describe('parseRestrictionFreeText', () => {
  it('splits comma-separated custom exclusions into solver tokens', () => {
    const parsed = parseRestrictionFreeText('mushrooms, cilantro');
    expect(parsed.map((r) => r.token).sort()).toEqual(['cilantro', 'mushroom']);
  });

  it('extracts food words from a sentence so they reach the solver', () => {
    const parsed = parseRestrictionFreeText("I'll never eat peanuts or shrimp");
    const tokens = parsed.map((r) => r.token);
    expect(tokens).toEqual(expect.arrayContaining(['peanut', 'shrimp']));
  });
});

describe('custom exclusions reach the solver', () => {
  it('every token from free text excludes matching staple foods', () => {
    const parsed = parseRestrictionFreeText('beef, peanut butter');
    const tokens = parsed.map((r) => r.token);
    expect(isFoodExcluded(bySlug('ground-beef-90'), tokens)).toBe(true);
    expect(isFoodExcluded(bySlug('peanut-butter'), tokens)).toBe(true);
    expect(isFoodExcluded(bySlug('banana'), tokens)).toBe(false);
  });

  it('merges structured chips with free text without dropping either', () => {
    const merged = mergeRestrictions([{ label: 'Dairy' }], 'shellfish, mushrooms');
    const labels = merged.map((r) => r.label.toLowerCase());
    expect(labels.some((l) => l.includes('dairy'))).toBe(true);
    expect(labels.some((l) => l.includes('shellfish'))).toBe(true);
    expect(labels.some((l) => l.includes('mushroom'))).toBe(true);
  });
});
