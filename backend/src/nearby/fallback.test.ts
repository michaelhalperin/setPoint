import { describe, expect, it } from 'vitest';
import { fallbackSuggestions, nearestWoltCity } from './fallback.js';

describe('nearestWoltCity', () => {
  it('picks the Wolt city page for where the user is', () => {
    expect(nearestWoltCity(29.55, 34.95)).toBe('eilat');
    expect(nearestWoltCity(32.79, 35.53)).toBe('tiberias-area');
    expect(nearestWoltCity(32.16, 34.81)).toBe('tel-aviv'); // Herzliya sits under Tel Aviv on Wolt
  });
});

describe('fallbackSuggestions', () => {
  it('gives three different searches sized to the gap, in the nearest city', () => {
    const out = fallbackSuggestions({ lat: 29.55, lng: 34.95, gapKcal: 800, avoid: new Set() });
    expect(out).toHaveLength(3);
    expect(new Set(out.map((d) => d.woltUrl)).size).toBe(3);
    expect(out[0]!.kcal).toBe(800);
    for (const d of out) expect(d.woltUrl).toMatch(/^https:\/\/wolt\.com\/en\/isr\/eilat\/search\?q=/);
  });

  it('leaves out what the user avoids', () => {
    const out = fallbackSuggestions({ lat: 32.79, lng: 35.53, gapKcal: 700, avoid: new Set(['vegan']) });
    expect(out.length).toBeGreaterThan(0);
    for (const d of out) expect(d.tags ?? []).toContain('vegan');
    const noFish = fallbackSuggestions({ lat: 32.79, lng: 35.53, gapKcal: 700, avoid: new Set(['fish']) });
    for (const d of noFish) expect(d.allergens).not.toContain('fish');
  });
});
