import type { PrismaClient } from '@prisma/client';
import { describe, expect, it } from 'vitest';
import { localDayRange } from '../engine/index.js';
import { listMealsForDate } from './listMeals.js';

const NOW = new Date('2026-09-01T18:00:00Z'); // 14:00 in New York

type AnyRow = Record<string, unknown>;

function fakePrisma(over: { user?: AnyRow | null; meals?: AnyRow[] } = {}) {
  const meals = over.meals ?? [];
  return {
    user: {
      findUnique: async () =>
        over.user === undefined ? { timezone: 'America/New_York' } : over.user,
    },
    meal: {
      findMany: async ({ where }: { where?: AnyRow }) => {
        const range = where?.loggedAt as { gte?: Date; lt?: Date } | undefined;
        return meals.filter((m) => {
          const t = (m.loggedAt as Date).getTime();
          if (range?.gte && t < range.gte.getTime()) return false;
          if (range?.lt && t >= range.lt.getTime()) return false;
          return true;
        });
      },
    },
  } as unknown as PrismaClient;
}

const meal = (over: AnyRow): AnyRow => ({
  id: 'm1',
  kcal: 600,
  proteinG: 30,
  carbsG: 40,
  fatG: 12,
  source: 'TEXT',
  rawInput: 'oats',
  ...over,
});

describe('localDayRange', () => {
  it('snaps a US-eastern YYYY-MM-DD onto local midnight, not UTC midnight', () => {
    const { start, end } = localDayRange('2026-09-01', 'America/New_York');
    expect(localDayRange('2026-09-01', 'UTC').start.toISOString()).toBe('2026-09-01T00:00:00.000Z');
    // EDT is UTC-4 in September.
    expect(start.toISOString()).toBe('2026-09-01T04:00:00.000Z');
    expect(end.toISOString()).toBe('2026-09-02T04:00:00.000Z');
  });
});

describe('listMealsForDate', () => {
  it('returns only meals on the requested local date, oldest first', async () => {
    const prisma = fakePrisma({
      meals: [
        meal({ id: 'yesterday', loggedAt: new Date('2026-08-31T22:00:00Z'), rawInput: 'late dinner' }),
        meal({ id: 'breakfast', loggedAt: new Date('2026-09-01T12:00:00Z'), rawInput: 'oats', kcal: 420 }),
        meal({ id: 'lunch', loggedAt: new Date('2026-09-01T16:00:00Z'), rawInput: 'burrito', kcal: 780 }),
        meal({ id: 'tomorrow', loggedAt: new Date('2026-09-02T12:00:00Z'), rawInput: 'eggs' }),
      ],
    });

    const view = await listMealsForDate({ prisma, now: NOW }, 'u1', '2026-09-01');

    expect(view.date).toBe('2026-09-01');
    expect(view.meals.map((m) => m.id)).toEqual(['breakfast', 'lunch']);
    expect(view.meals[0]).toMatchObject({ summary: 'oats', kcal: 420, source: 'TEXT' });
  });

  it('defaults to today in the user timezone when no date is given', async () => {
    const prisma = fakePrisma({
      meals: [meal({ id: 'today', loggedAt: new Date('2026-09-01T15:00:00Z') })],
    });
    const view = await listMealsForDate({ prisma, now: NOW }, 'u1');
    expect(view.date).toBe('2026-09-01');
    expect(view.meals).toHaveLength(1);
  });
});
