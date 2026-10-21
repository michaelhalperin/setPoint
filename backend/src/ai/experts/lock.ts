import type { PrismaClient } from '@prisma/client';
import { LOCK_TTL_MS, TRIPS_LOCK_24H, TRIPS_LOCK_7D } from './kinds.js';

export function lockActive(lockedUntil: Date | null | undefined, now = new Date()): boolean {
  return !!lockedUntil && lockedUntil.getTime() > now.getTime();
}

export async function recordTrip(
  prisma: PrismaClient,
  input: {
    userId: string;
    conversationId: string | null;
    layer: string;
    code: string;
    userMessage?: string;
    discardedReply?: string;
    now?: Date;
  },
): Promise<{ lockedUntil: Date | null }> {
  const now = input.now ?? new Date();
  await prisma.expertSafetyTrip.create({
    data: {
      userId: input.userId,
      conversationId: input.conversationId,
      layer: input.layer,
      code: input.code,
      userMessage: input.userMessage?.slice(0, 500) ?? null,
      discardedReply: input.discardedReply?.slice(0, 500) ?? null,
      createdAt: now,
    },
  });

  const since7 = new Date(now.getTime() - 7 * 86_400_000);
  const trips = await prisma.expertSafetyTrip.findMany({
    where: { userId: input.userId, createdAt: { gte: since7 } },
    select: { createdAt: true },
  });
  const in24 = trips.filter((t) => t.createdAt.getTime() >= now.getTime() - 86_400_000).length;
  const shouldLock = in24 >= TRIPS_LOCK_24H || trips.length >= TRIPS_LOCK_7D;
  if (!shouldLock || !input.conversationId) return { lockedUntil: null };

  const lockedUntil = new Date(now.getTime() + LOCK_TTL_MS);
  await prisma.expertConversation.update({
    where: { id: input.conversationId },
    data: { lockedUntil },
  });
  return { lockedUntil };
}
