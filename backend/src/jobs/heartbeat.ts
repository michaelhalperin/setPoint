import type { PrismaClient } from '@prisma/client';

/** Run times kept on the heartbeat row, so the ops dashboard can draw gaps. */
const KEEP_MS = 48 * 3_600_000;

/** A second scheduler calling right after one finished is skipped, so two of them never double-send. */
export const MIN_GAP_MS = 120_000;

export function ranTooRecently(lastRunAt: Date | null | undefined, now: number = Date.now()): boolean {
  return !!lastRunAt && now - lastRunAt.getTime() < MIN_GAP_MS;
}

export async function recordHeartbeat(
  prisma: PrismaClient,
  job: string,
  startedAt: Date,
  ok: boolean,
  summary: unknown,
): Promise<void> {
  const now = Date.now();
  const durationMs = now - startedAt.getTime();
  const previous = await prisma.schedulerHeartbeat.findUnique({ where: { job }, select: { summary: true } });
  const earlier = (previous?.summary as { runs?: unknown } | null)?.runs;
  const runs = [...(Array.isArray(earlier) ? earlier.filter((r): r is number => typeof r === 'number') : []), now]
    .filter((t) => now - t <= KEEP_MS)
    .slice(-400);
  const stored = { ...(summary && typeof summary === 'object' ? (summary as object) : {}), runs };
  await prisma.schedulerHeartbeat.upsert({
    where: { job },
    create: { job, lastRunAt: new Date(now), lastOk: ok, durationMs, summary: stored },
    update: { lastRunAt: new Date(now), lastOk: ok, durationMs, summary: stored },
  });
}
