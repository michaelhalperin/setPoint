import { describe, expect, it } from 'vitest';
import { sampleVenues } from '../data/nearbyVenues.js';
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
