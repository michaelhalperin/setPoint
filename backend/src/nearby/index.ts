/**
 * Order nearby: dishes from a list we keep per area, ranked by how well they
 * fill what the user still needs. SetPoint never orders — each dish carries a
 * Wolt link the app opens, and the user adds it and pays there.
 */

import { isFoodExcluded } from '../solver/exclusions.js';

export type DishKind = 'BOWL' | 'WRAP' | 'DRINK' | 'PLATE';

export type NearbyDish = {
  id: string;
  name: string;
  kcal: number;
  proteinG: number;
  carbsG?: number;
  fatG?: number;
  kind: DishKind;
  /** Allergen tokens, same vocabulary as DietaryRestriction.token ("peanut", "dairy"). */
  allergens: string[];
  /** 'vegan' or 'vegetarian' when the dish is; fish dishes count for pescatarians by allergen. */
  tags?: string[];
  /** Opens Wolt on this dish. Null for sample data. */
  woltUrl: string | null;
};

export type NearbyVenue = {
  id: string;
  name: string;
  lat: number;
  lng: number;
  /** Opens Wolt on the venue, when a dish has no link of its own. */
  woltUrl: string | null;
  dishes: NearbyDish[];
};

export type RankedVenue = {
  id: string;
  name: string;
  distanceKm: number;
  woltUrl: string | null;
  /** Dishes that fit, best first. */
  dishes: NearbyDish[];
};

export const NEARBY_RADIUS_KM = 3;
const MAX_VENUES = 12;

/** Great-circle distance in km. */
export function distanceKm(aLat: number, aLng: number, bLat: number, bLng: number): number {
  const rad = (d: number) => (d * Math.PI) / 180;
  const dLat = rad(bLat - aLat);
  const dLng = rad(bLng - aLng);
  const h = Math.sin(dLat / 2) ** 2 + Math.cos(rad(aLat)) * Math.cos(rad(bLat)) * Math.sin(dLng / 2) ** 2;
  return 6371 * 2 * Math.asin(Math.min(1, Math.sqrt(h)));
}

/**
 * Venues within reach, each with its dishes that pass the user's hard
 * exclusions (allergens, vegan/vegetarian/pescatarian, foods named outright),
 * closest to the gap first. Venues sort by their best dish's fit,
 * then distance.
 */
export function rankNearby(
  venues: NearbyVenue[],
  opts: { lat: number; lng: number; gapKcal: number; avoid: Set<string>; radiusKm?: number },
): RankedVenue[] {
  const radius = opts.radiusKm ?? NEARBY_RADIUS_KM;
  const fit = (d: NearbyDish) => Math.abs(d.kcal - opts.gapKcal);
  const avoid = [...opts.avoid];
  return venues
    .map((v) => {
      const km = distanceKm(opts.lat, opts.lng, v.lat, v.lng);
      const dishes = v.dishes
        .filter((d) => !isFoodExcluded({ name: d.name, allergens: d.allergens, tags: d.tags ?? [] }, avoid))
        .sort((a, b) => fit(a) - fit(b) || b.proteinG - a.proteinG);
      return { id: v.id, name: v.name, distanceKm: Math.round(km * 10) / 10, woltUrl: v.woltUrl, dishes };
    })
    .filter((v) => v.distanceKm <= radius && v.dishes.length > 0)
    .sort((a, b) => fit(a.dishes[0]!) - fit(b.dishes[0]!) || a.distanceKm - b.distanceKm)
    .slice(0, MAX_VENUES);
}
