import { describe, expect, it } from 'vitest';
import { NEARBY_VENUES, sampleVenues } from '../data/nearbyVenues.js';
import { distanceKm, rankNearby, type NearbyVenue } from './index.js';

const here = { lat: 32.06, lng: 34.77 };

describe('rankNearby', () => {
  it('puts the dish closest to the gap first, and the venue with the best fit first', () => {
    const ranked = rankNearby(sampleVenues(here.lat, here.lng), { ...here, gapKcal: 700, avoid: new Set() });
    expect(ranked[0]!.dishes[0]!.kcal).toBe(700);
    for (const venue of ranked) {
      const fits = venue.dishes.map((d) => Math.abs(d.kcal - 700));
      expect(fits).toEqual([...fits].sort((a, b) => a - b));
    }
  });

  it('drops dishes with an allergen the user avoids, and venues left with none', () => {
    const ranked = rankNearby(sampleVenues(here.lat, here.lng), { ...here, gapKcal: 600, avoid: new Set(['gluten']) });
    const names = ranked.flatMap((v) => v.dishes.map((d) => d.name));
    expect(names.some((n) => n.includes('wrap') || n.includes('pasta'))).toBe(false);
    expect(ranked.map((v) => v.name)).not.toContain('Lavash Lane');
  });

  it('keeps a vegetarian to vegetarian and vegan dishes', () => {
    const ranked = rankNearby(NEARBY_VENUES, { lat: 32.08, lng: 34.78, gapKcal: 700, avoid: new Set(['vegetarian']) });
    const dishes = ranked.flatMap((v) => v.dishes);
    expect(dishes.length).toBeGreaterThan(0);
    for (const d of dishes) expect(d.tags?.some((t) => t === 'vegan' || t === 'vegetarian')).toBe(true);
  });

  it('keeps only places within the radius', () => {
    const far: NearbyVenue = {
      id: 'far', name: 'Far away', lat: here.lat + 0.2, lng: here.lng, woltUrl: null,
      dishes: [{ id: 'd', name: 'Bowl', kcal: 700, proteinG: 40, kind: 'BOWL', allergens: [], woltUrl: null }],
    };
    expect(rankNearby([far], { ...here, gapKcal: 700, avoid: new Set() })).toEqual([]);
  });

  it('measures distance in km', () => {
    expect(distanceKm(here.lat, here.lng, here.lat + 0.009, here.lng)).toBeCloseTo(1, 1);
  });
});

describe('NEARBY_VENUES', () => {
  const dishes = NEARBY_VENUES.flatMap((v) => v.dishes.map((d) => ({ venue: v, dish: d })));

  it('has around a hundred dishes, each opening Wolt on itself', () => {
    expect(dishes.length).toBeGreaterThanOrEqual(100);
    for (const { venue, dish } of dishes) {
      expect(dish.woltUrl).toBe(`${venue.woltUrl}/itemid-${dish.id}`);
    }
  });

  it('has unique ids and believable numbers', () => {
    expect(new Set(NEARBY_VENUES.map((v) => v.id)).size).toBe(NEARBY_VENUES.length);
    expect(new Set(dishes.map(({ dish }) => dish.id)).size).toBe(dishes.length);
    for (const { dish } of dishes) {
      expect(dish.kcal).toBeGreaterThanOrEqual(300);
      expect(dish.kcal).toBeLessThanOrEqual(1300);
      const fromMacros = dish.proteinG * 4 + (dish.carbsG ?? 0) * 4 + (dish.fatG ?? 0) * 9;
      expect(Math.abs(fromMacros - dish.kcal) / dish.kcal).toBeLessThan(0.15);
    }
  });

  it('sits in central Tel Aviv', () => {
    for (const v of NEARBY_VENUES) expect(distanceKm(32.08, 34.78, v.lat, v.lng)).toBeLessThan(5);
  });
});
