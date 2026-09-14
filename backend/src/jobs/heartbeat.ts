import type { PrismaClient } from '@prisma/client';

export async function recordHeartbeat(
  prisma: PrismaClient,
  job: string,
  startedAt: Date,
  ok: boolean,
  summary: unknown,
): Promise<void> {
  const durationMs = Date.now() - startedAt.getTime();
  await prisma.schedulerHeartbeat.upsert({
    where: { job },
    create: { job, lastRunAt: new Date(), lastOk: ok, durationMs, summary: summary as object },
    update: { lastRunAt: new Date(), lastOk: ok, durationMs, summary: summary as object },
  });
}
