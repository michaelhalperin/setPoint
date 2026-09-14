import type { PrismaClient } from '@prisma/client';

export type RateLimitDecision = { allowed: boolean; retryAfterSeconds: number };

/** Counts one hit against `key` and says whether it's within `limit` per window. */
export type RateLimiter = (key: string, limit: number, windowSeconds: number, now?: Date) => Promise<RateLimitDecision>;

/**
 * Fixed-window counter in Postgres, so every serverless instance shares one
 * count (an in-memory map only limits a single warm lambda). One atomic
 * upsert per hit.
 */
export function postgresRateLimiter(db: () => PrismaClient): RateLimiter {
  return async (key, limit, windowSeconds, now = new Date()) => {
    const windowMs = windowSeconds * 1000;
    const windowStart = Math.floor(now.getTime() / windowMs) * windowMs;
    const windowEnd = new Date(windowStart + windowMs);
    const bucket = `${key}:${windowStart}`;

    // Prisma stores DateTime as UTC in a zone-less column; convert explicitly so
    // the server's TimeZone setting can't shift the window end.
    const rows = await db().$queryRaw<{ count: number }[]>`
      INSERT INTO "RateLimitBucket" ("key", "count", "windowEnd")
      VALUES (${bucket}, 1, (${windowEnd.toISOString()}::timestamptz AT TIME ZONE 'UTC'))
      ON CONFLICT ("key") DO UPDATE SET "count" = "RateLimitBucket"."count" + 1
      RETURNING "count"`;
    const count = Number(rows[0]?.count ?? 1);
    return {
      allowed: count <= limit,
      retryAfterSeconds: Math.max(1, Math.ceil((windowEnd.getTime() - now.getTime()) / 1000)),
    };
  };
}

/** Drops finished windows. Run from the daily cron. */
export async function pruneRateLimitBuckets(prisma: PrismaClient, now: Date = new Date()): Promise<number> {
  const { count } = await prisma.rateLimitBucket.deleteMany({ where: { windowEnd: { lt: now } } });
  return count;
}
