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

export function heartbeatStale(lastRunAt: Date | null | undefined, now = new Date(), maxAgeMin = 20): boolean {
  if (!lastRunAt) return true;
  return now.getTime() - lastRunAt.getTime() > maxAgeMin * 60_000;
}
