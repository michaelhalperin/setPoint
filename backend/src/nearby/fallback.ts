import { isFoodExcluded } from '../solver/exclusions.js';
import { distanceKm, type NearbyDish } from './index.js';

/**
 * When nothing on our list is near the user: a few kinds of dish sized to the
 * gap, each opening Wolt's own search for it in the nearest Wolt city, so Wolt
 * shows what's open around them. Nothing is collected for this.
 */

type GenericDish = Omit<NearbyDish, 'woltUrl'> & { search: string };

const GENERIC_DISHES: GenericDish[] = [
  { id: 'generic-poke', name: 'A salmon or chicken poke bowl', search: 'poke', kcal: 700, proteinG: 38, carbsG: 85, fatG: 20, kind: 'BOWL', allergens: ['fish', 'soy', 'sesame'] },
  { id: 'generic-chicken-plate', name: 'A grilled chicken plate with two sides', search: 'grill', kcal: 800, proteinG: 55, carbsG: 80, fatG: 24, kind: 'PLATE', allergens: [] },
  { id: 'generic-shawarma-plate', name: 'A shawarma plate with sides', search: 'shawarma', kcal: 1000, proteinG: 55, carbsG: 95, fatG: 42, kind: 'PLATE', allergens: ['gluten', 'wheat', 'sesame'] },
  { id: 'generic-shawarma-pita', name: 'Shawarma in a pita', search: 'shawarma', kcal: 750, proteinG: 42, carbsG: 68, fatG: 32, kind: 'WRAP', allergens: ['gluten', 'wheat', 'sesame'] },
  { id: 'generic-schnitzel-plate', name: 'A schnitzel plate', search: 'schnitzel', kcal: 950, proteinG: 45, carbsG: 90, fatG: 42, kind: 'PLATE', allergens: ['gluten', 'wheat', 'egg', 'sesame'] },
  { id: 'generic-pad-thai', name: 'Pad thai with chicken', search: 'pad thai', kcal: 800, proteinG: 38, carbsG: 100, fatG: 26, kind: 'BOWL', allergens: ['egg', 'peanut', 'soy', 'fish'] },
  { id: 'generic-chicken-salad', name: 'A big chicken salad', search: 'salad', kcal: 520, proteinG: 40, carbsG: 25, fatG: 26, kind: 'BOWL', allergens: [] },
  { id: 'generic-chicken-sandwich', name: 'A chicken sandwich', search: 'sandwich', kcal: 700, proteinG: 42, carbsG: 65, fatG: 28, kind: 'WRAP', allergens: ['gluten', 'wheat', 'egg'] },
  { id: 'generic-tofu-poke', name: 'A tofu poke bowl', search: 'poke', kcal: 600, proteinG: 22, carbsG: 85, fatG: 18, kind: 'BOWL', allergens: ['soy', 'sesame'], tags: ['vegan'] },
  { id: 'generic-falafel', name: 'Falafel in a pita with hummus', search: 'falafel', kcal: 700, proteinG: 20, carbsG: 85, fatG: 30, kind: 'WRAP', allergens: ['gluten', 'wheat', 'sesame'], tags: ['vegan'] },
];

/** Wolt's Israeli city pages, by a point in each (a few for the spread-out ones). */
const WOLT_CITIES: [slug: string, lat: number, lng: number][] = [
  ['tel-aviv', 32.08, 34.78], ['tel-aviv', 32.16, 34.81], ['tel-aviv', 32.08, 34.81],
  ['jerusalem', 31.78, 35.21], ['mevaseret-zion-area', 31.8, 35.15], ['beit-shemesh-area', 31.75, 34.99],
  ['haifa', 32.81, 34.99], ['haifa', 32.84, 35.08], ['yokneam', 32.66, 35.11], ['pardes-hanna', 32.47, 34.97],
  ['beer-sheva', 31.25, 34.79], ['netivot-sderot-area', 31.42, 34.59], ['eilat', 29.56, 34.95],
  ['petah-tikva', 32.09, 34.88], ['modiin', 31.9, 35.01],
  ['ashdod-and-lachish-area', 31.8, 34.65], ['ashdod-and-lachish-area', 31.61, 34.77], ['ashkelon', 31.67, 34.57],
  ['rishon-lezion-hashfela-area', 31.96, 34.8], ['rishon-lezion-hashfela-area', 31.9, 34.81], ['rishon-lezion-hashfela-area', 32.02, 34.76],
  ['hasharon', 32.28, 34.86], ['hasharon', 32.18, 34.88], ['hasharon', 32.33, 34.92],
  ['acre-nahariya-area', 32.96, 35.09], ['karmiel-area', 32.92, 35.3], ['maalot-tarshiha-area', 33.02, 35.27],
  ['afula-emek-yizrael-area', 32.61, 35.29], ['nazareth---nof-hagalil-area', 32.7, 35.3], ['sakhnin-area', 32.86, 35.3],
  ['tiberias-area', 32.79, 35.53], ['rosh-pinna---zefat-area', 32.97, 35.5], ['kiryat-shmona-area', 33.21, 35.57],
];

export function nearestWoltCity(lat: number, lng: number): string {
  let best = WOLT_CITIES[0]!;
  for (const c of WOLT_CITIES) {
    if (distanceKm(lat, lng, c[1], c[2]) < distanceKm(lat, lng, best[1], best[2])) best = c;
  }
  return best[0];
}

/** Up to three kinds of dish that fit the gap, each a different search, minus what the user avoids. */
export function fallbackSuggestions(opts: { lat: number; lng: number; gapKcal: number; avoid: Set<string> }): NearbyDish[] {
  const city = nearestWoltCity(opts.lat, opts.lng);
  const avoid = [...opts.avoid];
  const fit = (d: GenericDish) => Math.abs(d.kcal - opts.gapKcal);
  const picked: GenericDish[] = [];
  for (const d of GENERIC_DISHES.filter((g) => !isFoodExcluded({ name: g.name, allergens: g.allergens, tags: g.tags ?? [] }, avoid)).sort(
    (a, b) => fit(a) - fit(b) || b.proteinG - a.proteinG,
  )) {
    if (picked.some((p) => p.search === d.search)) continue;
    picked.push(d);
    if (picked.length === 3) break;
  }
  return picked.map(({ search, ...d }) => ({
    ...d,
    woltUrl: `https://wolt.com/en/isr/${city}/search?q=${encodeURIComponent(search)}`,
  }));
}
