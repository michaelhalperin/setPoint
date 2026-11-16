import type { PrismaClient } from '@prisma/client';
import { queuePhotoDeletion } from '../photos/cleanup.js';
import type { PhotoStore } from '../photos/store.js';
import { MealNotFoundError } from './updateMeal.js';
import { toMealSummaries, type MealSummary } from './summary.js';

export class PhotoStorageUnavailableError extends Error {}

export type MealPhotoDeps = { prisma: PrismaClient; photos: PhotoStore | null };

/** Puts a photo on a meal that's already logged, replacing the one it had. */
export async function setMealPhoto(
  deps: MealPhotoDeps,
  userId: string,
  mealId: string,
  image: { data: string; mediaType: string },
): Promise<MealSummary> {
  if (!deps.photos) throw new PhotoStorageUnavailableError('photo storage is not configured');
  const existing = await deps.prisma.meal.findFirst({ where: { id: mealId, userId }, select: { photoKey: true } });
  if (!existing) throw new MealNotFoundError('meal not found');

  const key = await deps.photos.put(userId, Buffer.from(image.data, 'base64'), image.mediaType);
  let updated;
  try {
    updated = await deps.prisma.meal.update({ where: { id: mealId }, data: { photoKey: key, photoUrl: null } });
  } catch (err) {
    await queuePhotoDeletion(deps.prisma, { kind: 'object', key }, err);
    throw err;
  }
  if (existing.photoKey) await dropPhoto(deps, existing.photoKey);
  const [summary] = await toMealSummaries([updated], deps.photos);
  return summary!;
}

/** Takes the photo off a meal and deletes it from storage. */
export async function clearMealPhoto(deps: MealPhotoDeps, userId: string, mealId: string): Promise<MealSummary> {
  const existing = await deps.prisma.meal.findFirst({ where: { id: mealId, userId }, select: { photoKey: true } });
  if (!existing) throw new MealNotFoundError('meal not found');
  const updated = await deps.prisma.meal.update({ where: { id: mealId }, data: { photoKey: null, photoUrl: null } });
  if (existing.photoKey) await dropPhoto(deps, existing.photoKey);
  const [summary] = await toMealSummaries([updated], deps.photos);
  return summary!;
}

async function dropPhoto(deps: MealPhotoDeps, key: string): Promise<void> {
  try {
    await deps.photos?.delete(key);
  } catch (err) {
    // The meal is already updated; the daily cron retries the delete.
    await queuePhotoDeletion(deps.prisma, { kind: 'object', key }, err);
  }
}
