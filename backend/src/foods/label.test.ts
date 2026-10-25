import { describe, expect, it } from 'vitest';
import { labelFacts } from './label.js';

const reading = {
  readable: true,
  name: 'במבה',
  brand: 'אסם',
  servingG: 25,
  kcal100g: 535.4,
  proteinG100g: 15.04,
  carbsG100g: 49,
  fatG100g: 31,
};

describe('labelFacts', () => {
  it('rounds a readable label into cache facts', () => {
    expect(labelFacts(reading)).toEqual({
      name: 'במבה',
      brand: 'אסם',
      servingG: 25,
      kcal100g: 535,
      proteinG100g: 15,
      carbsG100g: 49,
      fatG100g: 31,
    });
  });

  it('drops unreadable or impossible readings', () => {
    expect(labelFacts({ ...reading, readable: false })).toBeNull();
    expect(labelFacts({ ...reading, kcal100g: 0 })).toBeNull();
    expect(labelFacts({ ...reading, carbsG100g: 90, fatG100g: 40 })).toBeNull();
  });

  it('names a product from its brand when the name is not on the label', () => {
    expect(labelFacts({ ...reading, name: ' ' })?.name).toBe('אסם');
    expect(labelFacts({ ...reading, name: '', brand: '' })?.name).toBe('Scanned product');
  });
});
