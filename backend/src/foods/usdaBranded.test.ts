import { describe, expect, it } from 'vitest';
import { parseFdcBranded } from './usdaBranded.js';

const cheerios = {
  gtinUpc: '00016000275287',
  description: 'CHEERIOS CEREAL',
  brandOwner: 'General Mills Sales Inc.',
  servingSize: 28,
  servingSizeUnit: 'GRM',
  foodNutrients: [
    { nutrientId: 1003, unitName: 'G', value: 12.8 },
    { nutrientId: 1004, unitName: 'G', value: 6.41 },
    { nutrientId: 1005, unitName: 'G', value: 74.4 },
    { nutrientId: 1008, unitName: 'KCAL', value: 359 },
    // Later copies are per serving and must not win.
    { nutrientId: 1008, unitName: 'KCAL', value: 100 },
  ],
};

describe('parseFdcBranded', () => {
  it('matches the GTIN whatever its zero padding and keeps per-100 g values', () => {
    const facts = parseFdcBranded(['016000275287', '0016000275287'], { foods: [cheerios] });
    expect(facts).toEqual({
      name: 'Cheerios Cereal',
      brand: 'General Mills Sales Inc.',
      servingG: 28,
      kcal100g: 359,
      proteinG100g: 12.8,
      carbsG100g: 74.4,
      fatG100g: 6.41,
    });
  });

  it('ignores a different product and one without energy', () => {
    expect(parseFdcBranded(['012345678905'], { foods: [cheerios] })).toBeNull();
    const noEnergy = { ...cheerios, foodNutrients: cheerios.foodNutrients.filter((n) => n.nutrientId !== 1008) };
    expect(parseFdcBranded(['016000275287'], { foods: [noEnergy] })).toBeNull();
  });
});
