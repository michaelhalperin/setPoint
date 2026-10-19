import type { NearbyVenue } from '../nearby/index.js';

/**
 * The real list: places near our users, their dishes with our kcal and protein
 * estimates, and the Wolt link for each dish (from Wolt's Share button). Empty
 * until it's filled in — the app then shows "no places near you yet".
 */
export const NEARBY_VENUES: NearbyVenue[] = [];

/**
 * Made-up places for trying the screen (NEARBY_SAMPLE_VENUES=true). They're
 * placed around wherever the user is, and have no Wolt links.
 */
export function sampleVenues(lat: number, lng: number): NearbyVenue[] {
  const at = (dLat: number, dLng: number) => ({ lat: lat + dLat, lng: lng + dLng });
  return [
    {
      id: 'sample-grain-grill',
      name: 'Grain & Grill',
      ...at(0.006, 0.003),
      woltUrl: null,
      dishes: [
        { id: 'gg-shawarma', name: 'Chicken shawarma bowl', kcal: 690, proteinG: 48, carbsG: 62, fatG: 24, kind: 'BOWL', allergens: ['sesame'], woltUrl: null },
        { id: 'gg-falafel', name: 'Falafel bowl with tahini', kcal: 640, proteinG: 22, carbsG: 70, fatG: 28, kind: 'BOWL', allergens: ['sesame'], woltUrl: null },
      ],
    },
    {
      id: 'sample-lavash-lane',
      name: 'Lavash Lane',
      ...at(-0.008, 0.005),
      woltUrl: null,
      dishes: [
        { id: 'll-halloumi', name: 'Halloumi and egg wrap', kcal: 610, proteinG: 32, carbsG: 48, fatG: 30, kind: 'WRAP', allergens: ['dairy', 'egg', 'gluten', 'wheat'], woltUrl: null },
        { id: 'll-steak', name: 'Steak wrap', kcal: 720, proteinG: 44, carbsG: 52, fatG: 32, kind: 'WRAP', allergens: ['gluten', 'wheat'], woltUrl: null },
      ],
    },
    {
      id: 'sample-peak-smoothies',
      name: 'Peak Smoothies',
      ...at(0.003, -0.004),
      woltUrl: null,
      dishes: [
        { id: 'ps-pb-shake', name: 'Peanut butter banana oat shake', kcal: 520, proteinG: 34, carbsG: 60, fatG: 16, kind: 'DRINK', allergens: ['peanut', 'dairy'], woltUrl: null },
        { id: 'ps-berry', name: 'Berry protein smoothie', kcal: 430, proteinG: 30, carbsG: 58, fatG: 8, kind: 'DRINK', allergens: ['dairy'], woltUrl: null },
      ],
    },
    {
      id: 'sample-pasta-corner',
      name: 'Pasta Corner',
      ...at(-0.012, -0.007),
      woltUrl: null,
      dishes: [
        { id: 'pc-pesto', name: 'Chicken pesto pasta', kcal: 760, proteinG: 44, carbsG: 80, fatG: 26, kind: 'PLATE', allergens: ['gluten', 'wheat', 'dairy', 'tree_nut'], woltUrl: null },
        { id: 'pc-tomato', name: 'Tomato pasta with meatballs', kcal: 700, proteinG: 38, carbsG: 84, fatG: 22, kind: 'PLATE', allergens: ['gluten', 'wheat'], woltUrl: null },
      ],
    },
  ];
}
