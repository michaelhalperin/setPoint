import { describe, expect, it } from 'vitest';
import { shapeFromMessage } from './suggestPlate.js';

describe('shapeFromMessage', () => {
  it('maps the ten-minute chip', () => {
    expect(shapeFromMessage('I only have 10 minutes')).toEqual({ requireNoCook: true, requireDrinkable: false });
    expect(shapeFromMessage('יש לי רק 10 דקות').requireNoCook).toBe(true);
  });

  it('maps the drink chip', () => {
    expect(shapeFromMessage('Something I can drink')).toEqual({ requireNoCook: false, requireDrinkable: true });
    expect(shapeFromMessage('משהו שאפשר לשתות').requireDrinkable).toBe(true);
  });

  it('leaves what’s-left unconstrained', () => {
    expect(shapeFromMessage('What’s left today?')).toEqual({ requireNoCook: false, requireDrinkable: false });
  });
});
