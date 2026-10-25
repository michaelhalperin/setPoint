/**
 * USDA FoodData Central branded foods (~450k packaged products, label data
 * submitted by manufacturers) as the second barcode source. FDC keeps GTINs at
 * whatever length the brand sent — often zero-padded to 14 — so every form of
 * the code is asked for in one query.
 *
 * Public domain (CC0). Citation: U.S. Department of Agriculture, Agricultural
 * Research Service. FoodData Central. fdc.nal.usda.gov.
 */
import { env } from '../env.js';
import type { BarcodeFoodFacts } from './barcode.js';

const FDC_SEARCH_URL = 'https://api.nal.usda.gov/fdc/v1/foods/search';
const FDC_TIMEOUT_MS = 4_000;

type FdcNutrient = { nutrientId?: number; unitName?: string; value?: number };

export type FdcBrandedFood = {
  gtinUpc?: string;
  description?: string;
  brandName?: string;
  brandOwner?: string;
  servingSize?: number;
  servingSizeUnit?: string;
  foodNutrients?: FdcNutrient[];
};

export type FdcSearchResponse = { foods?: FdcBrandedFood[] };

const NUTRIENT = { kcal: 1008, protein: 1003, fat: 1004, carbs: 1005 } as const;

const stripZeros = (code: string): string => code.replace(/^0+/, '');

/** The first food whose GTIN is one of `codes`, as per-100 g facts. Pure. */
export function parseFdcBranded(codes: string[], payload: FdcSearchResponse): BarcodeFoodFacts | null {
  const wanted = new Set(codes.map(stripZeros));
  const food = payload.foods?.find((f) => f.gtinUpc && wanted.has(stripZeros(f.gtinUpc)));
  if (!food?.description) return null;

  // Search results repeat nutrients (per 100 g first, then label/serving copies).
  const first = (id: number): FdcNutrient | undefined => food.foodNutrients?.find((n) => n.nutrientId === id);
  const energy = first(NUTRIENT.kcal);
  let kcal100g = typeof energy?.value === 'number' ? energy.value : null;
  if (kcal100g != null && energy?.unitName?.toUpperCase() === 'KJ') kcal100g = Math.round(kcal100g / 4.184);
  if (kcal100g == null || kcal100g <= 0) return null;

  const unit = food.servingSizeUnit?.toUpperCase();
  const servingG = food.servingSize && food.servingSize > 0 && (unit === 'G' || unit === 'GRM' || unit === 'ML' || unit === 'MLT')
    ? food.servingSize
    : null;

  return {
    name: titleCase(food.description).slice(0, 200),
    brand: (food.brandName || food.brandOwner)?.trim().slice(0, 120) || null,
    servingG,
    kcal100g,
    proteinG100g: first(NUTRIENT.protein)?.value ?? 0,
    carbsG100g: first(NUTRIENT.carbs)?.value ?? 0,
    fatG100g: first(NUTRIENT.fat)?.value ?? 0,
  };
}

/**
 * Branded lookup for the barcode fallback. Works on the shared DEMO_KEY (a
 * handful of calls an hour); set FDC_API_KEY (free at api.data.gov) for real use.
 */
export async function fetchUsdaBranded(codes: string[]): Promise<BarcodeFoodFacts | null> {
  const forms = new Set<string>();
  for (const code of codes) {
    const bare = stripZeros(code);
    for (const len of [12, 13, 14]) if (bare.length <= len) forms.add(bare.padStart(len, '0'));
    forms.add(code);
  }
  const url = new URL(FDC_SEARCH_URL);
  url.searchParams.set('api_key', env.FDC_API_KEY || 'DEMO_KEY');
  url.searchParams.set('query', [...forms].map((f) => `gtinUpc:${f}`).join(' OR '));
  url.searchParams.set('dataType', 'Branded');
  url.searchParams.set('pageSize', '5');

  const res = await fetch(url, { headers: { Accept: 'application/json' }, signal: AbortSignal.timeout(FDC_TIMEOUT_MS) });
  if (!res.ok) throw new Error(`FoodData Central ${res.status}`);
  return parseFdcBranded(codes, (await res.json()) as FdcSearchResponse);
}

/** FDC descriptions are often SHOUTED; brands and short words stay readable. */
function titleCase(text: string): string {
  const trimmed = text.trim();
  if (trimmed !== trimmed.toUpperCase()) return trimmed;
  return trimmed.toLowerCase().replace(/(^|[\s(/-])(\p{L})/gu, (_, sep: string, ch: string) => sep + ch.toUpperCase());
}
