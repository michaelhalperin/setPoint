import type { PrismaClient } from '@prisma/client';
import { langOf, type Lang } from './index.js';

/** The language the user picked in the app. English until they say otherwise (or if it can't be read). */
export async function userLang(prisma: PrismaClient, userId: string): Promise<Lang> {
  try {
    const user = await prisma.user.findUnique({ where: { id: userId }, select: { language: true } });
    return langOf(user?.language);
  } catch {
    return 'en';
  }
}
