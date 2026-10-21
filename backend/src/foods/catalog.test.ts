import { describe, expect, it } from 'vitest';
import {
  defaultGrams,
  macrosForGrams,
  normalizeSearchQuery,
  rankCatalogName,
  searchCatalog,
  searchCatalogRows,
  type CatalogFoodRow,
} from './catalog.js';

const chicken: CatalogFoodRow = {
  id: 'c1',
  fdcId: 1,
  name: 'Chicken, broilers or fryers, breast, meat only, cooked, roasted',
  category: 'Poultry',
  servingG: 85,
  servingDesc: '3 oz',
  kcal100g: 165,
  proteinG100g: 31,
  carbsG100g: 0,
  fatG100g: 3.6,
  dataType: 'sr_legacy',
};

const broth: CatalogFoodRow = {
  id: 'c2',
  fdcId: 2,
  name: 'Soup, chicken broth, canned, condensed',
  category: 'Soups',
  servingG: 126,
  servingDesc: '0.5 cup',
  kcal100g: 32,
  proteinG100g: 2.3,
  carbsG100g: 2,
  fatG100g: 2,
  dataType: 'sr_legacy',
};

const banana: CatalogFoodRow = {
  id: 'c3',
  fdcId: 3,
  name: 'Banana, raw',
  category: 'Fruits',
  servingG: 118,
  servingDesc: '1 medium',
  kcal100g: 89,
  proteinG100g: 1.1,
  carbsG100g: 23,
  fatG100g: 0.3,
  dataType: 'foundation',
};

describe('normalizeSearchQuery', () => {
  it('trims and rejects tiny or huge queries', () => {
    expect(normalizeSearchQuery('  chicken  ')).toBe('chicken');
    expect(normalizeSearchQuery('a')).toBeNull();
    expect(normalizeSearchQuery('x'.repeat(81))).toBeNull();
  });
});

describe('searchCatalogRows', () => {
  it('ranks prefix and shorter names ahead of a contains match', () => {
    const hits = searchCatalogRows([broth, chicken, banana], 'chicken');
    expect(hits.map((h) => h.id)).toEqual(['c1', 'c2']);
  });

  it('prefers foundation when names match equally', () => {
    const raw: CatalogFoodRow = { ...banana, id: 'c4', fdcId: 4, dataType: 'sr_legacy' };
    const hits = searchCatalogRows([raw, banana], 'banana');
    expect(hits[0]?.id).toBe('c3');
  });
});

describe('rankCatalogName', () => {
  it('scores exact, prefix, then contains', () => {
    expect(rankCatalogName('Banana, raw', 'banana')).toBe(1);
    expect(rankCatalogName('Soup, chicken broth', 'chicken')).toBe(2);
    expect(rankCatalogName('Chicken breast', 'chicken')).toBe(1);
  });
});

describe('macrosForGrams', () => {
  it('scales per-100g macros to the portion', () => {
    expect(macrosForGrams(chicken, 85)).toMatchObject({ grams: 85, kcal: 140, proteinG: 26.4 });
    expect(defaultGrams(chicken)).toBe(85);
    expect(defaultGrams({ servingG: null })).toBe(100);
  });
});

describe('searchCatalog', () => {
  it('asks prisma for a case-insensitive contains and ranks the result', async () => {
    const rows = [broth, chicken];
    const foods = await searchCatalog(
      {
        prisma: {
          catalogFood: {
            findMany: async ({ where }) => {
              expect(where.name.contains).toBe('Chicken');
              expect(where.name.mode).toBe('insensitive');
              return rows;
            },
          },
        },
      },
      'Chicken',
    );
    expect(foods[0]?.id).toBe('c1');
  });
});
