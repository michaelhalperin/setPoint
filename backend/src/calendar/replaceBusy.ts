import type { PrismaClient } from '@prisma/client';

export type BusyBlockInput = { start: Date; end: Date; allDay?: boolean };

export async function replaceBusyWindow(
  prisma: PrismaClient,
  userId: string,
  from: Date,
  to: Date,
  blocks: BusyBlockInput[],
): Promise<number> {
  const rows = blocks
    .filter((b) => b.end > b.start)
    .map((b) => ({
      userId,
      start: b.start < from ? from : b.start,
      end: b.end > to ? to : b.end,
      allDay: b.allDay ?? false,
    }))
    .filter((b) => b.end > b.start);
  await prisma.$transaction(async (tx) => {
    await tx.calendarBusyBlock.deleteMany({
      where: {
        userId,
        start: { lt: to },
        end: { gt: from },
      },
    });
    if (rows.length > 0) {
      await tx.calendarBusyBlock.createMany({ data: rows });
    }
  });
  return rows.length;
}

export async function clearBusy(prisma: PrismaClient, userId: string): Promise<void> {
  await prisma.calendarBusyBlock.deleteMany({ where: { userId } });
}
