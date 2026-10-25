/**
 * Barcode lookup: Open Food Facts first, then an optional second source (USDA
 * branded foods), with a shared BarcodeFood cache. Products read off a photo of
 * the label land in the same cache, so a miss only has to be filled once.
 * Unknown codes return null so the app can offer the label photo or typing.
 */

import { env } from '../env.js';

export type BarcodeFoodView = {
  code: string;
  name: string;
  brand: string | null;
  servingG: number | null;
  kcal100g: number;
  proteinG100g: number;
  carbsG100g: number;
  fatG100g: number;
  fetchedAt: string;
};

export type OffProduct = {
  status: number;
  product?: {
    product_name?: string;
    product_name_en?: string;
    generic_name?: string;
    brands?: string;
    serving_quantity?: number | string;
    serving_size?: string;
    nutriments?: Record<string, unknown>;
  };
};

export type BarcodeLookupDeps = {
  prisma: {
    barcodeFood: {
      findUnique: (args: { where: { code: string } }) => Promise<BarcodeFoodRow | null>;
      upsert: (args: {
        where: { code: string };
        create: BarcodeFoodWrite;
        update: Omit<BarcodeFoodWrite, 'code'>;
      }) => Promise<BarcodeFoodRow>;
    };
  };
  fetchProduct: (code: string) => Promise<OffProduct | null>;
  /** Tried with every form of the code when Open Food Facts has nothing usable. */
  fetchFallback?: (codes: string[]) => Promise<BarcodeFoodFacts | null>;
  now?: Date;
};

/** What a source knows about a product, before it is keyed and timestamped. */
export type BarcodeFoodFacts = Omit<BarcodeFoodWrite, 'code' | 'fetchedAt'>;

type BarcodeFoodRow = {
  code: string;
  name: string;
  brand: string | null;
  servingG: number | null;
  kcal100g: number;
  proteinG100g: number;
  carbsG100g: number;
  fatG100g: number;
  fetchedAt: Date;
};

type BarcodeFoodWrite = {
  code: string;
  name: string;
  brand: string | null;
  servingG: number | null;
  kcal100g: number;
  proteinG100g: number;
  carbsG100g: number;
  fatG100g: number;
  fetchedAt: Date;
};

const round1 = (n: number): number => Math.round(n * 10) / 10;

/** Digits only, 8–14 characters (EAN-8 through EAN-14 / UPC). */
export function normalizeBarcode(raw: string): string | null {
  const code = raw.replace(/\s+/g, '');
  if (!/^\d{8,14}$/.test(code)) return null;
  return code;
}

/**
 * Every form the same product may be stored under: a 12-digit UPC-A is also a
 * 13-digit EAN with a leading 0, a UPC-E is a shortened UPC-A, and GTIN-14s pad
 * with zeros. The scanned code comes first.
 */
export function barcodeVariants(code: string): string[] {
  const out = new Set<string>([code]);
  if (code.length === 8 && (code[0] === '0' || code[0] === '1')) {
    const upcA = expandUpcE(code);
    if (upcA) {
      out.add(upcA);
      out.add(`0${upcA}`);
    }
  }
  if (code.length === 12) out.add(`0${code}`);
  if (code.length === 13 && code.startsWith('0')) out.add(code.slice(1));
  if (code.length === 14 && code.startsWith('0')) {
    out.add(code.slice(1));
    if (code.startsWith('00')) out.add(code.slice(2));
  }
  return [...out];
}

/** UPC-E (number system, six digits, check digit) back to its 12-digit UPC-A. */
export function expandUpcE(code: string): string | null {
  if (!/^[01]\d{7}$/.test(code)) return null;
  const [ns, d1, d2, d3, d4, d5, d6, check] = code.split('');
  let body: string;
  if (d6 === '0' || d6 === '1' || d6 === '2') body = `${d1}${d2}${d6}0000${d3}${d4}${d5}`;
  else if (d6 === '3') body = `${d1}${d2}${d3}00000${d4}${d5}`;
  else if (d6 === '4') body = `${d1}${d2}${d3}${d4}00000${d5}`;
  else body = `${d1}${d2}${d3}${d4}${d5}0000${d6}`;
  return `${ns}${body}${check}`;
}

export function parseOffProduct(code: string, payload: OffProduct, fetchedAt: Date): BarcodeFoodWrite | null {
  if (payload.status !== 1 || !payload.product) return null;
  const product = payload.product;
  // Many local products only carry a name in their own language (product_name_he…).
  const name = (product.product_name || product.product_name_en || localizedName(product) || product.generic_name || '').trim();
  if (!name) return null;
  const nutriments = product.nutriments ?? {};
  const kcal100g = kcalPer100g(nutriments) ?? kcalFromMacros(nutriments);
  if (kcal100g == null) return null;
  const servingG = servingGrams(product);
  return {
    code,
    name: name.slice(0, 200),
    brand: product.brands?.trim().slice(0, 120) || null,
    servingG,
    kcal100g,
    proteinG100g: num(nutriments['proteins_100g']) ?? 0,
    carbsG100g: num(nutriments['carbohydrates_100g']) ?? 0,
    fatG100g: num(nutriments['fat_100g']) ?? 0,
    fetchedAt,
  };
}

export function macrosForServings(
  food: Pick<BarcodeFoodRow, 'servingG' | 'kcal100g' | 'proteinG100g' | 'carbsG100g' | 'fatG100g'>,
  servings: number,
): { grams: number; kcal: number; proteinG: number; carbsG: number; fatG: number } {
  const servingG = food.servingG && food.servingG > 0 ? food.servingG : 100;
  const grams = servingG * servings;
  const factor = grams / 100;
  return {
    grams,
    kcal: Math.round(food.kcal100g * factor),
    proteinG: round1(food.proteinG100g * factor),
    carbsG: round1(food.carbsG100g * factor),
    fatG: round1(food.fatG100g * factor),
  };
}

export function toBarcodeFoodView(row: BarcodeFoodRow): BarcodeFoodView {
  return {
    code: row.code,
    name: row.name,
    brand: row.brand,
    servingG: row.servingG,
    kcal100g: row.kcal100g,
    proteinG100g: row.proteinG100g,
    carbsG100g: row.carbsG100g,
    fatG100g: row.fatG100g,
    fetchedAt: row.fetchedAt.toISOString(),
  };
}

/** Open Food Facts entries get corrected; a cached product older than this is re-fetched. */
export const BARCODE_CACHE_MAX_AGE_MS = 30 * 86_400_000;

export async function lookupBarcode(deps: BarcodeLookupDeps, rawCode: string): Promise<BarcodeFoodView | null> {
  const code = normalizeBarcode(rawCode);
  if (!code) return null;
  const now = deps.now ?? new Date();

  const cached = await deps.prisma.barcodeFood.findUnique({ where: { code } });
  if (cached && now.getTime() - cached.fetchedAt.getTime() < BARCODE_CACHE_MAX_AGE_MS) {
    return toBarcodeFoodView(cached);
  }

  const codes = barcodeVariants(code);
  let found: BarcodeFoodFacts | null = null;
  let failure: unknown;
  for (const variant of codes) {
    try {
      const payload = await deps.fetchProduct(variant);
      const parsed = payload ? parseOffProduct(code, payload, now) : null;
      if (parsed) {
        const { code: _code, fetchedAt: _at, ...facts } = parsed;
        found = facts;
        break;
      }
    } catch (err) {
      // Open Food Facts down or slow: don't hammer it with the other forms.
      failure = err;
      break;
    }
  }
  if (!found && deps.fetchFallback) {
    try {
      found = await deps.fetchFallback(codes);
    } catch (err) {
      failure ??= err;
    }
  }
  if (!found) {
    // A stale entry beats no entry; an outage with nothing cached is an error, not a miss.
    if (cached) return toBarcodeFoodView(cached);
    if (failure) throw failure;
    return null;
  }

  return toBarcodeFoodView(await saveBarcodeFood(deps.prisma, code, found, now));
}

/** Writes a product into the shared cache under `code` — used by lookups and label reads. */
export async function saveBarcodeFood(
  prisma: BarcodeLookupDeps['prisma'],
  code: string,
  facts: BarcodeFoodFacts,
  now: Date,
): Promise<BarcodeFoodRow> {
  const parsed: BarcodeFoodWrite = { code, ...facts, fetchedAt: now };
  return prisma.barcodeFood.upsert({
    where: { code },
    create: parsed,
    update: {
      name: parsed.name,
      brand: parsed.brand,
      servingG: parsed.servingG,
      kcal100g: parsed.kcal100g,
      proteinG100g: parsed.proteinG100g,
      carbsG100g: parsed.carbsG100g,
      fatG100g: parsed.fatG100g,
      fetchedAt: parsed.fetchedAt,
    },
  });
}

const OFF_URL = 'https://world.openfoodfacts.org/api/v2/product';
const OFF_USER_AGENT = `SetPoint/1.0 (https://setpoint.app; ${env.SUPPORT_EMAIL})`;
const OFF_TIMEOUT_MS = 5_000;

/** One retry: Open Food Facts answers 503 when it is busy, and a second try usually lands. */
export async function fetchOpenFoodFacts(code: string): Promise<OffProduct | null> {
  for (let attempt = 0; ; attempt++) {
    try {
      const res = await fetch(`${OFF_URL}/${code}.json`, {
        headers: { Accept: 'application/json', 'User-Agent': OFF_USER_AGENT },
        signal: AbortSignal.timeout(OFF_TIMEOUT_MS),
      });
      if (res.status === 404) return null;
      if (res.status >= 500 && attempt === 0) continue;
      if (!res.ok) throw new Error(`Open Food Facts ${res.status}`);
      return (await res.json()) as OffProduct;
    } catch (err) {
      if (attempt === 0 && (err as Error).name === 'TimeoutError') continue;
      throw err;
    }
  }
}

function localizedName(product: NonNullable<OffProduct['product']>): string | undefined {
  for (const [key, value] of Object.entries(product)) {
    if (key.startsWith('product_name_') && typeof value === 'string' && value.trim()) return value;
  }
  return undefined;
}

function kcalPer100g(nutriments: Record<string, unknown>): number | null {
  const direct = num(nutriments['energy-kcal_100g']) ?? num(nutriments['energy-kcal_value']);
  if (direct != null && direct > 0) return direct;
  const kj = num(nutriments['energy-kj_100g']) ?? num(nutriments['energy_100g']);
  if (kj != null && kj > 0) return Math.round(kj / 4.184);
  return null;
}

/** Atwater 4/4/9 when a product lists macros but no energy. */
function kcalFromMacros(nutriments: Record<string, unknown>): number | null {
  const p = num(nutriments['proteins_100g']);
  const c = num(nutriments['carbohydrates_100g']);
  const f = num(nutriments['fat_100g']);
  if (p == null && c == null && f == null) return null;
  const kcal = Math.round(4 * (p ?? 0) + 4 * (c ?? 0) + 9 * (f ?? 0));
  return kcal > 0 ? kcal : null;
}

function servingGrams(product: NonNullable<OffProduct['product']>): number | null {
  const qty = num(product.serving_quantity);
  if (qty != null && qty > 0) return qty;
  const size = product.serving_size?.match(/([\d.]+)\s*g/i);
  if (size) {
    const grams = Number(size[1]);
    return grams > 0 ? grams : null;
  }
  return null;
}

function num(value: unknown): number | null {
  if (typeof value === 'number' && Number.isFinite(value)) return value;
  if (typeof value === 'string' && value.trim() !== '') {
    const n = Number(value);
    return Number.isFinite(n) ? n : null;
  }
  return null;
}
