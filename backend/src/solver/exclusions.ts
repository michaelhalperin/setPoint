import type { SolverFood } from './types.js';

const LIFESTYLE_TOKENS = new Set(['vegetarian', 'vegan', 'pescatarian']);

/** Normalize a raw restriction string for matching. */
export function normalizeToken(raw: string): string {
  return raw.trim().toLowerCase().replace(/\s+/g, '_');
}

/**
 * Whether a food must be excluded given the user's restriction tokens. Always a
 * hard filter (plan §2: "never a soft preference"):
 *   - the token names one of the food's allergens, or
 *   - the token is a lifestyle diet the food does not satisfy, or
 *   - the token appears in the food's name (catches "beef", "pork", "shrimp", ...).
 */
export function isFoodExcluded(food: SolverFood, tokens: string[]): boolean {
  const name = food.name.toLowerCase();

  for (const raw of tokens) {
    const token = normalizeToken(raw);
    if (!token) continue;

    if (food.allergens.includes(token)) return true;

    if (token === 'vegetarian' && !(food.tags.includes('vegetarian') || food.tags.includes('vegan'))) {
      return true;
    }
    if (token === 'vegan' && !food.tags.includes('vegan')) return true;
    if (
      token === 'pescatarian' &&
      !(food.tags.includes('vegetarian') || food.tags.includes('vegan') || food.allergens.includes('fish'))
    ) {
      return true;
    }

    if (!LIFESTYLE_TOKENS.has(token) && name.includes(token.replace(/_/g, ' '))) return true;
  }

  return false;
}

export function filterAllowedFoods(foods: SolverFood[], tokens: string[]): SolverFood[] {
  return foods.filter((food) => !isFoodExcluded(food, tokens));
}
