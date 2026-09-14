import type { PrismaClient } from '@prisma/client';

/** Opens a real tier-3 conversation for this user, or resumes one that is still open. */
export async function startTalk(
  prisma: PrismaClient,
  userId: string,
): Promise<{ checkInId: string }> {
  const open = await prisma.escalationConversation.findFirst({
    where: { userId, resolvedAt: null, checkInId: { not: null } },
    orderBy: { createdAt: 'desc' },
    select: { checkInId: true },
  });
  if (open?.checkInId) return { checkInId: open.checkInId };

  const checkIn = await prisma.checkIn.create({
    data: {
      userId,
      tier: 3,
      status: 'PENDING',
      deliveryStatus: 'CREATED',
    },
  });
  await prisma.escalationConversation.create({
    data: { userId, checkInId: checkIn.id },
  });
  return { checkInId: checkIn.id };
}
