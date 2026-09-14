import type { PrismaClient } from '@prisma/client';
import { describe, expect, it, vi } from 'vitest';
import type { MealParser } from '../ai/parseMeal.js';
import { AiQuotaExceededError } from '../ai/quota.js';
import { EmptyMealError, MealParsingUnavailableError, logMeal } from './logMeal.js';

type AnyRow = Record<string, unknown>;

function fakePrisma() {
  const meals: AnyRow[] = [];
  const checkIns: AnyRow[] = [];
  const escalationStates: AnyRow[] = [];
  const prescriptions: AnyRow[] = [];
  const savedMeals: AnyRow[] = [];
  const barcodeFoods: AnyRow[] = [];
  let seq = 0;

  const match = (row: AnyRow, where: AnyRow = {}): boolean =>
    Object.entries(where).every(([k, v]) => {
      if (v && typeof v === 'object' && 'in' in v) return (v.in as unknown[]).includes(row[k]);
      if (v && typeof v === 'object' && 'lt' in v) return (row[k] as number) < (v.lt as number);
      return row[k] === v;
    });

  const coll = (rows: AnyRow[], p: string) => ({
    create: async ({ data }: { data: AnyRow }) => {
      const row = { id: `${p}_${(seq += 1)}`, createdAt: new Date(), ...data };
      rows.push(row);
      return row;
    },
    findMany: async ({ where }: { where?: AnyRow } = {}) => rows.filter((r) => match(r, where)),
    findFirst: async ({ where }: { where?: AnyRow } = {}) => rows.find((r) => match(r, where)) ?? null,
    findUnique: async ({ where }: { where: AnyRow }) => {
      const key = (where.userId_clientId as AnyRow | undefined) ?? where;
      return rows.find((r) => match(r, key)) ?? null;
    },
    update: async ({ where, data }: { where: AnyRow; data: AnyRow }) => {
      const row = rows.find((r) => match(r, where));
      if (row) Object.assign(row, data);
      return row;
    },
    updateMany: async ({ where, data }: { where: AnyRow; data: AnyRow }) => {
      let count = 0;
      for (const row of rows.filter((r) => match(r, where))) {
        Object.assign(row, data);
        count += 1;
      }
      return { count };
    },
    upsert: async ({ where, create, update }: { where: AnyRow; create: AnyRow; update: AnyRow }) => {
      const row = rows.find((r) => match(r, where));
      if (row) {
        Object.assign(row, update);
        return row;
      }
      const created = { ...where, ...create };
      rows.push(created);
      return created;
    },
  });

  return {
    __tables: { meals, checkIns, escalationStates, prescriptions, savedMeals, barcodeFoods },
    meal: coll(meals, 'm'),
    checkIn: coll(checkIns, 'ci'),
    escalationState: coll(escalationStates, 'es'),
    prescription: coll(prescriptions, 'rx'),
    savedMeal: coll(savedMeals, 'sm'),
    barcodeFood: coll(barcodeFoods, 'bf'),
  };
}

const parser: MealParser = vi.fn(async () => ({
  items: [{ name: 'Bagel', quantity: '1', kcal: 257, proteinG: 10, carbsG: 50, fatG: 1.5 }],
  kcal: 257,
  proteinG: 10,
  carbsG: 50,
  fatG: 1.5,
  confidence: 0.6,
  quality: 'high' as const,
  needsReview: false,
  summary: 'Bagel',
}));

describe('logMeal', () => {
  it('AI-parses free text, stores the meal, and resolves an open check-in', async () => {
    const prisma = fakePrisma();
    prisma.__tables.checkIns.push({ id: 'ci_open', userId: 'u1', status: 'PENDING', tier: 1, createdAt: new Date() });
    prisma.__tables.escalationStates.push({ userId: 'u1', consecutiveMisses: 2, currentTier: 2, backedOffUntil: new Date() });

    const res = await logMeal({ prisma: prisma as unknown as PrismaClient, parseMeal: parser }, 'u1', {
      text: 'a bagel',
    });

    expect(res.meal.kcal).toBe(257);
    expect(res.meal.source).toBe('TEXT');
    expect(res.parsed?.summary).toBe('Bagel');
    expect(res.resolvedCheckInId).toBe('ci_open');
    expect(prisma.__tables.checkIns[0]).toMatchObject({ status: 'LOGGED' });
    expect(prisma.__tables.escalationStates[0]).toMatchObject({ consecutiveMisses: 0, currentTier: 1, backedOffUntil: null });
  });

  it('puts the photo in object storage and keeps only its key on the meal', async () => {
    const prisma = fakePrisma();
    const put = vi.fn(async () => 'meals/u1/photo.jpg');
    const photos = { put, signedUrl: vi.fn(), delete: vi.fn(), deleteAllForUser: vi.fn() };
    await logMeal({ prisma: prisma as unknown as PrismaClient, parseMeal: parser, photos }, 'u1', {
      image: { data: 'AAAA', mediaType: 'image/jpeg' },
    });
    expect(put).toHaveBeenCalledWith('u1', Buffer.from('AAAA', 'base64'), 'image/jpeg');
    expect(prisma.__tables.meals[0]).toMatchObject({
      source: 'PHOTO',
      photoKey: 'meals/u1/photo.jpg',
      items: [{ name: 'Bagel', quantity: '1', kcal: 257, proteinG: 10, carbsG: 50, fatG: 1.5 }],
    });
    expect(prisma.__tables.meals[0]).not.toHaveProperty('photoUrl');
  });

  it('still logs the meal when the photo upload fails', async () => {
    vi.spyOn(console, 'error').mockImplementation(() => {});
    const prisma = fakePrisma();
    const put = vi.fn(async () => {
      throw new Error('storage down');
    });
    const photos = { put, signedUrl: vi.fn(), delete: vi.fn(), deleteAllForUser: vi.fn() };
    const res = await logMeal({ prisma: prisma as unknown as PrismaClient, parseMeal: parser, photos }, 'u1', {
      image: { data: 'AAAA', mediaType: 'image/jpeg' },
    });
    expect(res.meal.kcal).toBe(257);
    expect(prisma.__tables.meals[0]).toMatchObject({ photoKey: null });
  });

  it('charges the AI quota only for parsing, and stops before the model when over', async () => {
    const prisma = fakePrisma();
    const db = prisma as unknown as PrismaClient;
    const quota = vi.fn(async () => {});
    await logMeal({ prisma: db, parseMeal: parser, quota }, 'u1', { text: 'a bagel' });
    await logMeal({ prisma: db, parseMeal: parser, quota }, 'u1', { macros: { kcal: 300 } });
    expect(quota).toHaveBeenCalledTimes(1);
    expect(quota).toHaveBeenCalledWith('meal_parse');

    const model = vi.fn(parser);
    const refuse = vi.fn(async () => {
      throw new AiQuotaExceededError('meal_parse', 60);
    });
    await expect(
      logMeal({ prisma: db, parseMeal: model, quota: refuse }, 'u1', { text: 'another bagel' }),
    ).rejects.toBeInstanceOf(AiQuotaExceededError);
    expect(model).not.toHaveBeenCalled();
    expect(prisma.__tables.meals).toHaveLength(2);
  });

  it('accepts explicit macros without calling the parser', async () => {
    const prisma = fakePrisma();
    const spy = vi.fn(parser);
    const res = await logMeal({ prisma: prisma as unknown as PrismaClient, parseMeal: spy }, 'u1', {
      macros: { kcal: 600, proteinG: 40 },
    });
    expect(res.meal.source).toBe('MANUAL');
    expect(res.parsed).toBeNull();
    expect(spy).not.toHaveBeenCalled();
  });

  it('marks the prescription accepted when logging from one', async () => {
    const prisma = fakePrisma();
    prisma.__tables.prescriptions.push({ id: 'rx_1', userId: 'u1', status: 'OFFERED' });
    await logMeal({ prisma: prisma as unknown as PrismaClient, parseMeal: parser }, 'u1', {
      macros: { kcal: 450 },
      prescriptionId: 'rx_1',
    });
    expect(prisma.__tables.prescriptions[0]).toMatchObject({ status: 'ACCEPTED' });
  });

  it('logs a prescription\'s totals when only prescriptionId is given', async () => {
    const prisma = fakePrisma();
    prisma.__tables.prescriptions.push({
      id: 'rx_2',
      userId: 'u1',
      status: 'OFFERED',
      totalKcal: 620,
      totalProteinG: 48,
      totalCarbsG: 55,
      totalFatG: 14,
    });
    const res = await logMeal({ prisma: prisma as unknown as PrismaClient, parseMeal: null }, 'u1', {
      prescriptionId: 'rx_2',
    });
    expect(res.meal).toMatchObject({ kcal: 620, proteinG: 48, source: 'PRESCRIPTION' });
    expect(prisma.__tables.prescriptions[0]).toMatchObject({ status: 'ACCEPTED' });
    expect(res.parsed).toBeNull();
  });

  it('errors when text logging is attempted with no parser configured', async () => {
    const prisma = fakePrisma();
    await expect(
      logMeal({ prisma: prisma as unknown as PrismaClient, parseMeal: null }, 'u1', { text: 'a bagel' }),
    ).rejects.toBeInstanceOf(MealParsingUnavailableError);
  });

  it('errors on an empty payload', async () => {
    const prisma = fakePrisma();
    await expect(
      logMeal({ prisma: prisma as unknown as PrismaClient, parseMeal: parser }, 'u1', {}),
    ).rejects.toBeInstanceOf(EmptyMealError);
  });

  it('logs a saved meal without calling the parser and bumps useCount', async () => {
    const prisma = fakePrisma();
    prisma.__tables.savedMeals.push({
      id: 'sm_1',
      userId: 'u1',
      name: 'Usual oats',
      items: [{ name: 'Oats', quantity: '1 bowl', kcal: 420, proteinG: 18, carbsG: 60, fatG: 10 }],
      kcal: 420,
      proteinG: 18,
      carbsG: 60,
      fatG: 10,
      useCount: 2,
      lastUsedAt: null,
    });
    const spy = vi.fn(parser);
    const res = await logMeal({ prisma: prisma as unknown as PrismaClient, parseMeal: spy }, 'u1', {
      savedMealId: 'sm_1',
      clientId: '7d3f1a52-51c2-4a39-9a7e-0f6c1f1f8b11',
    });
    expect(res.meal).toMatchObject({ kcal: 420, source: 'SAVED' });
    expect(spy).not.toHaveBeenCalled();
    expect(prisma.__tables.meals[0]).toMatchObject({ rawInput: 'Usual oats', parsedByAI: false });
    expect(prisma.__tables.savedMeals[0]).toMatchObject({ useCount: 3 });
  });

  it('logs a barcode from cache without calling the parser', async () => {
    const prisma = fakePrisma();
    prisma.__tables.barcodeFoods.push({
      code: '3017620422003',
      name: 'Greek yogurt',
      brand: 'Chobani',
      servingG: 170,
      kcal100g: 100,
      proteinG100g: 10,
      carbsG100g: 4,
      fatG100g: 5,
      fetchedAt: new Date(),
    });
    const spy = vi.fn(parser);
    const fetchProduct = vi.fn(async () => null);
    const res = await logMeal(
      { prisma: prisma as unknown as PrismaClient, parseMeal: spy, barcode: { fetchProduct } },
      'u1',
      { barcode: '3017620422003', servings: 2 },
    );
    expect(res.meal.source).toBe('BARCODE');
    expect(res.meal.kcal).toBe(340);
    expect(spy).not.toHaveBeenCalled();
    expect(fetchProduct).not.toHaveBeenCalled();
    expect(prisma.__tables.meals[0]?.items).toMatchObject([{ name: 'Greek yogurt', quantity: '2 servings', kcal: 340 }]);
  });

  it('rejects an unknown barcode without parsing', async () => {
    const prisma = fakePrisma();
    const spy = vi.fn(parser);
    await expect(
      logMeal(
        { prisma: prisma as unknown as PrismaClient, parseMeal: spy, barcode: { fetchProduct: async () => ({ status: 0 }) } },
        'u1',
        { barcode: '00000000' },
      ),
    ).rejects.toBeInstanceOf(EmptyMealError);
    expect(spy).not.toHaveBeenCalled();
    expect(prisma.__tables.meals).toHaveLength(0);
  });

  it('does not close a tier-3 conversation when an unrelated meal is logged', async () => {
    const prisma = fakePrisma();
    prisma.__tables.checkIns.push({ id: 'ci_t3', userId: 'u1', status: 'PENDING', tier: 3, createdAt: new Date() });
    const res = await logMeal({ prisma: prisma as unknown as PrismaClient, parseMeal: parser }, 'u1', {
      text: 'a bagel',
    });
    expect(res.resolvedCheckInId).toBeNull();
    expect(prisma.__tables.checkIns[0]).toMatchObject({ status: 'PENDING', tier: 3 });
  });

  it('returns the stored meal for a repeated clientId without parsing or charging again', async () => {
    const prisma = fakePrisma();
    const parse = vi.fn(parser);
    const quota = vi.fn(async () => {});
    const deps = { prisma: prisma as unknown as PrismaClient, parseMeal: parse, quota };
    const clientId = '7d3f1a52-51c2-4a39-9a7e-0f6c1f1f8b10';
    const eatenAt = new Date(Date.now() - 5 * 3600_000);

    const first = await logMeal(deps, 'u1', { text: 'a bagel', clientId, loggedAt: eatenAt });
    const retry = await logMeal(deps, 'u1', { text: 'a bagel', clientId, loggedAt: eatenAt });

    expect(retry.meal.id).toBe(first.meal.id);
    expect(prisma.__tables.meals).toHaveLength(1);
    expect(prisma.__tables.meals[0]).toMatchObject({ loggedAt: eatenAt, clientId });
    expect(parse).toHaveBeenCalledTimes(1);
    expect(quota).toHaveBeenCalledTimes(1);
  });
});
