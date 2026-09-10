import type { PrismaClient } from '@prisma/client';
import { describe, expect, it } from 'vitest';
import { MealNotFoundError, updateMeal } from './updateMeal.js';

function fakePrisma() {
  const meal = {
    id: 'meal_1',
    userId: 'user_1',
    loggedAt: new Date('2026-09-10T12:00:00Z'),
    source: 'PHOTO',
    rawInput: 'AI guess',
    photoUrl: 'data:image/jpeg;base64,AAAA',
    notes: 'Assumed a large portion',
    items: [],
    parseConfidence: 0.6,
    kcal: 600,
    proteinG: 20,
    carbsG: 70,
    fatG: 18,
  };

  return {
    __meal: meal,
    meal: {
      findFirst: async ({ where }: { where: { id: string; userId: string } }) =>
        where.id === meal.id && where.userId === meal.userId ? meal : null,
      update: async ({ data }: { data: Record<string, unknown> }) => {
        Object.assign(meal, data);
        return meal;
      },
    },
  };
}

describe('updateMeal', () => {
  it('persists corrected items and derives coherent totals', async () => {
    const prisma = fakePrisma();
    const result = await updateMeal({ prisma: prisma as unknown as PrismaClient }, 'user_1', 'meal_1', {
      summary: 'Chicken and rice',
      items: [
        { name: 'Chicken', quantity: '150 g', kcal: 250, proteinG: 42, carbsG: 0, fatG: 8 },
        { name: 'Rice', quantity: '1 cup', kcal: 210, proteinG: 4.2, carbsG: 45, fatG: 0.5 },
      ],
    });

    expect(result).toMatchObject({
      summary: 'Chicken and rice',
      kcal: 460,
      proteinG: 46.2,
      carbsG: 45,
      fatG: 8.5,
      photoUrl: 'data:image/jpeg;base64,AAAA',
      parseConfidence: null,
      notes: null,
    });
  });

  it('does not update a meal owned by someone else', async () => {
    const prisma = fakePrisma();
    await expect(
      updateMeal({ prisma: prisma as unknown as PrismaClient }, 'other_user', 'meal_1', {
        summary: 'Nope',
        items: [{ name: 'Food', quantity: '', kcal: 1, proteinG: 0, carbsG: 0, fatG: 0 }],
      }),
    ).rejects.toBeInstanceOf(MealNotFoundError);
  });
});
