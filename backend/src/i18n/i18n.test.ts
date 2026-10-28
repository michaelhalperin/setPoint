import { describe, expect, it } from 'vitest';
import { checkInCopy } from '../managerVoice/checkInCopy.js';
import { fallbackTierThree } from '../ai/tierThree.js';
import { closeCopy, lightMealCopy } from '../jobs/scoreConfidence.js';
import { namedSummary } from '../solver/prescribe.js';
import { STAPLE_FOODS } from '../data/stapleFoods.js';
import { FOOD_NAMES_HE } from './foodNames.js';
import { foodNameIn, langOf } from './index.js';

describe('Hebrew copy', () => {
  it('defaults to English and only switches on "he"', () => {
    expect(langOf(null)).toBe('en');
    expect(langOf('fr')).toBe('en');
    expect(langOf('he')).toBe('he');
  });

  it('names every staple food in Hebrew', () => {
    const missing = STAPLE_FOODS.map((f) => f.name).filter((n) => !FOOD_NAMES_HE[n]);
    expect(missing).toEqual([]);
    expect(foodNameIn('Whole milk', 'he')).toBe('חלב מלא');
    expect(foodNameIn('Whole milk', 'en')).toBe('Whole milk');
  });

  it('writes the check-in, light-meal and close lines in Hebrew', async () => {
    const line = checkInCopy({ tier: 1, goal: 'BULK', hoursSinceMeal: 5, kcalGap: 600, slot: 'lunch', lang: 'he' });
    expect(line).toBe('ארוחת הצהריים התפספסה. עברו 5 שעות מהארוחה האחרונה.');
    expect(lightMealCopy('snack_pm', null, 'he')).toContain('הנשנוש היה קל');
    expect(closeCopy(480, 'חלב מלא', 'he')).toContain('חסרות לך 480 קלוריות');
    expect(closeCopy(480, 'whole milk')).toBe("You're 480 kcal short today. Whole milk closes most of it.");
  });

  it('names plates in Hebrew', () => {
    expect(namedSummary({ items: [{ name: 'Whole milk', quantity: 2 }, { name: 'Almonds', quantity: 1 }] }, 'he')).toBe('2 × חלב מלא + שקדים');
  });

  it('answers the tier-3 chat in Hebrew when asked', async () => {
    const opener = fallbackTierThree.opener({ goal: 'BULK', recentMisses: 3, lang: 'he' });
    expect(opener).toContain('התזכורות');
    const reply = await fallbackTierThree.respond([{ role: 'user', content: 'אפשר להשהות את התזכורות?' }], { goal: 'BULK', recentMisses: 3, lang: 'he' });
    expect(reply.outcome).toBe('PAUSE_CHECKINS');
  });
});
