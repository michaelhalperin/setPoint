import { describe, expect, it } from 'vitest';
import { foodsFromUsdaDump, mapUsdaFood } from './usda.js';

const chicken = {
  fdcId: 171077,
  description: 'Chicken, broilers or fryers, breast, meat only, cooked, roasted',
  dataType: 'SR Legacy',
  foodCategory: { description: 'Poultry Products' },
  foodNutrients: [
    { nutrient: { id: 1008, name: 'Energy', unitName: 'kcal' }, amount: 165 },
    { nutrient: { id: 1003, name: 'Protein', unitName: 'g' }, amount: 31 },
    { nutrient: { id: 1005, name: 'Carbohydrate, by difference', unitName: 'g' }, amount: 0 },
    { nutrient: { id: 1004, name: 'Total lipid (fat)', unitName: 'g' }, amount: 3.6 },
  ],
  foodPortions: [{ gramWeight: 85, amount: 3, measureUnit: { name: 'oz' }, modifier: 'boneless' }],
};

describe('mapUsdaFood', () => {
  it('maps per-100g macros and a default serving', () => {
    expect(mapUsdaFood(chicken)).toMatchObject({
      fdcId: 171077,
      name: 'Chicken, broilers or fryers, breast, meat only, cooked, roasted',
      category: 'Poultry Products',
      servingG: 85,
      servingDesc: '3 oz boneless',
      kcal100g: 165,
      proteinG100g: 31,
      carbsG100g: 0,
      fatG100g: 3.6,
      dataType: 'sr_legacy',
    });
  });

  it('converts kJ when kcal is missing and skips foods without energy', () => {
    const oats = mapUsdaFood({
      fdcId: 1,
      description: 'Oats',
      dataType: 'Foundation',
      foodNutrients: [{ nutrient: { id: 1062, unitName: 'kJ' }, amount: 1674 }],
    });
    expect(oats?.kcal100g).toBe(400);
    expect(oats?.dataType).toBe('foundation');
    expect(oats?.servingG).toBe(100);

    expect(
      mapUsdaFood({
        fdcId: 2,
        description: 'Mystery',
        dataType: 'SR Legacy',
        foodNutrients: [{ nutrient: { id: 1003 }, amount: 10 }],
      }),
    ).toBeNull();
  });
});

describe('foodsFromUsdaDump', () => {
  it('reads FoundationFoods and SRLegacyFoods wrappers', () => {
    const foundation = foodsFromUsdaDump({
      FoundationFoods: [{ ...chicken, fdcId: 10, dataType: 'Foundation' }],
    });
    expect(foundation).toHaveLength(1);
    expect(foundation[0]?.dataType).toBe('foundation');

    const legacy = foodsFromUsdaDump({ SRLegacyFoods: [chicken] });
    expect(legacy).toHaveLength(1);
    expect(legacy[0]?.fdcId).toBe(171077);
  });
});
