/**
 * Open Food Facts barcode lookup, with a shared BarcodeFood cache.
 * Unknown codes return null so the app can fall back to typing.
 */

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
  now?: Date;
};

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

export function parseOffProduct(code: string, payload: OffProduct, fetchedAt: Date): BarcodeFoodWrite | null {
  if (payload.status !== 1 || !payload.product) return null;
  const product = payload.product;
  const name = (product.product_name || product.product_name_en || '').trim();
  if (!name) return null;
  const nutriments = product.nutriments ?? {};
  const kcal100g = kcalPer100g(nutriments);
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

export async function lookupBarcode(deps: BarcodeLookupDeps, rawCode: string): Promise<BarcodeFoodView | null> {
  const code = normalizeBarcode(rawCode);
  if (!code) return null;
  const now = deps.now ?? new Date();

  const cached = await deps.prisma.barcodeFood.findUnique({ where: { code } });
  if (cached) return toBarcodeFoodView(cached);

  const payload = await deps.fetchProduct(code);
  if (!payload) return null;
  const parsed = parseOffProduct(code, payload, now);
  if (!parsed) return null;

  const stored = await deps.prisma.barcodeFood.upsert({
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
  return toBarcodeFoodView(stored);
}

const OFF_URL = 'https://world.openfoodfacts.org/api/v2/product';
const OFF_USER_AGENT = 'SetPoint/0.1 (https://setpoint.app; support@setpoint.app)';

export async function fetchOpenFoodFacts(code: string): Promise<OffProduct | null> {
  const res = await fetch(`${OFF_URL}/${code}.json`, {
    headers: { Accept: 'application/json', 'User-Agent': OFF_USER_AGENT },
  });
  if (res.status === 404) return null;
  if (!res.ok) throw new Error(`Open Food Facts ${res.status}`);
  return (await res.json()) as OffProduct;
}

function kcalPer100g(nutriments: Record<string, unknown>): number | null {
  const direct = num(nutriments['energy-kcal_100g']) ?? num(nutriments['energy-kcal_value']);
  if (direct != null && direct > 0) return direct;
  const kj = num(nutriments['energy-kj_100g']) ?? num(nutriments['energy_100g']);
  if (kj != null && kj > 0) return Math.round(kj / 4.184);
  return null;
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
