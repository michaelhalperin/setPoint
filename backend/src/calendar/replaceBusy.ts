import type { PrismaClient } from '@prisma/client';

export async function replaceBusyWindow(
  prisma: PrismaClient,
  userId: string,
  from: Date,
  to: Date,
  blocks: { start: Date; end: Date }[],
): Promise<number> {
  await prisma.calendarBusyBlock.deleteMany({
    where: {
      userId,
      start: { lt: to },
      end: { gt: from },
    },
  });
  const rows = blocks
    .filter((b) => b.end > b.start)
    .map((b) => ({
      userId,
      start: b.start < from ? from : b.start,
      end: b.end > to ? to : b.end,
    }))
    .filter((b) => b.end > b.start);
  if (rows.length > 0) {
    await prisma.calendarBusyBlock.createMany({ data: rows });
  }
  return rows.length;
}

export async function clearBusy(prisma: PrismaClient, userId: string): Promise<void> {
  await prisma.calendarBusyBlock.deleteMany({ where: { userId } });
}
