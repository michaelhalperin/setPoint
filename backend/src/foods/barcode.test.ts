import { describe, expect, it, vi } from 'vitest';
import {
  lookupBarcode,
  macrosForServings,
  normalizeBarcode,
  parseOffProduct,
  type OffProduct,
} from './barcode.js';

const NOW = new Date('2026-09-14T12:00:00Z');

const offHit: OffProduct = {
  status: 1,
  product: {
    product_name: 'Greek yogurt',
    brands: 'Chobani',
    serving_quantity: 170,
    nutriments: {
      'energy-kcal_100g': 97,
      proteins_100g: 9,
      carbohydrates_100g: 3.6,
      fat_100g: 5,
    },
  },
};

function cachePrisma(rows: Record<string, unknown>[] = []) {
  return {
    barcodeFood: {
      findUnique: async ({ where }: { where: { code: string } }) =>
        rows.find((r) => r.code === where.code) ?? null,
      upsert: async ({ create }: { create: Record<string, unknown> }) => {
        const existing = rows.find((r) => r.code === create.code);
        if (existing) {
          Object.assign(existing, create);
          return existing;
        }
        rows.push(create);
        return create;
      },
    },
    __rows: rows,
  };
}

describe('normalizeBarcode', () => {
  it('keeps 8–14 digit codes and strips spaces', () => {
    expect(normalizeBarcode(' 3017620422003 ')).toBe('3017620422003');
    expect(normalizeBarcode('abc')).toBeNull();
    expect(normalizeBarcode('123')).toBeNull();
  });
});

describe('parseOffProduct', () => {
  it('maps a found product to per-100g macros', () => {
    const parsed = parseOffProduct('3017620422003', offHit, NOW);
    expect(parsed).toMatchObject({
      code: '3017620422003',
      name: 'Greek yogurt',
      brand: 'Chobani',
      servingG: 170,
      kcal100g: 97,
      proteinG100g: 9,
    });
  });

  it('returns null when Open Food Facts has no product or no energy', () => {
    expect(parseOffProduct('1', { status: 0 }, NOW)).toBeNull();
    expect(
      parseOffProduct('1', { status: 1, product: { product_name: 'Mystery', nutriments: {} } }, NOW),
    ).toBeNull();
  });

  it('falls back from kJ when kcal is missing', () => {
    const parsed = parseOffProduct(
      '1',
      { status: 1, product: { product_name: 'Oats', nutriments: { energy_100g: 1674 } } },
      NOW,
    );
    expect(parsed?.kcal100g).toBe(400);
  });
});

describe('macrosForServings', () => {
  it('scales the serving size, defaulting a missing serving to 100 g', () => {
    const food = { servingG: 170, kcal100g: 100, proteinG100g: 10, carbsG100g: 4, fatG100g: 5 };
    expect(macrosForServings(food, 1)).toMatchObject({ grams: 170, kcal: 170, proteinG: 17 });
    expect(macrosForServings(food, 2).kcal).toBe(340);
    expect(macrosForServings({ ...food, servingG: null }, 1).grams).toBe(100);
  });
});

describe('lookupBarcode', () => {
  it('returns the cache without calling Open Food Facts', async () => {
    const fetchProduct = vi.fn(async () => offHit);
    const prisma = cachePrisma([
      {
        code: '3017620422003',
        name: 'Cached yogurt',
        brand: 'Chobani',
        servingG: 170,
        kcal100g: 97,
        proteinG100g: 9,
        carbsG100g: 3.6,
        fatG100g: 5,
        fetchedAt: NOW,
      },
    ]);
    const food = await lookupBarcode(
      { prisma: prisma as never, fetchProduct, now: NOW },
      '3017620422003',
    );
    expect(food?.name).toBe('Cached yogurt');
    expect(fetchProduct).not.toHaveBeenCalled();
  });

  it('refreshes a stale cache entry and falls back to it when Open Food Facts fails', async () => {
    const old = new Date(NOW.getTime() - 40 * 86_400_000);
    const stale = {
      code: '3017620422003',
      name: 'Old yogurt',
      brand: null,
      servingG: 170,
      kcal100g: 97,
      proteinG100g: 9,
      carbsG100g: 3.6,
      fatG100g: 5,
      fetchedAt: old,
    };
    const refreshed = await lookupBarcode(
      { prisma: cachePrisma([{ ...stale }]) as never, fetchProduct: async () => offHit, now: NOW },
      '3017620422003',
    );
    expect(refreshed?.name).toBe('Greek yogurt');

    const fallback = await lookupBarcode(
      {
        prisma: cachePrisma([{ ...stale }]) as never,
        fetchProduct: async () => {
          throw new Error('timeout');
        },
        now: NOW,
      },
      '3017620422003',
    );
    expect(fallback?.name).toBe('Old yogurt');
  });

  it('fetches, caches, and returns a miss as null', async () => {
    const rows: Record<string, unknown>[] = [];
    const prisma = cachePrisma(rows);
    const hit = await lookupBarcode(
      { prisma: prisma as never, fetchProduct: async () => offHit, now: NOW },
      '3017620422003',
    );
    expect(hit?.name).toBe('Greek yogurt');
    expect(rows).toHaveLength(1);

    const miss = await lookupBarcode(
      { prisma: cachePrisma() as never, fetchProduct: async () => ({ status: 0 }), now: NOW },
      '00000000',
    );
    expect(miss).toBeNull();
  });
});
