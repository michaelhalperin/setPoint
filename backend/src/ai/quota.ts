import type { PrismaClient } from '@prisma/client';

/**
 * Per-user limits on the endpoints that call a paid model. Counted in Postgres
 * (the AiUsage table) rather than in memory: on serverless every warm instance
 * would keep its own counter, so an in-memory limiter doesn't actually limit.
 */
export type AiUsageKind = 'meal_parse' | 'tier3_message';

export type QuotaLimit = { windowMs: number; max: number };

const HOUR_MS = 3_600_000;
const DAY_MS = 24 * HOUR_MS;

export const AI_QUOTAS: Record<AiUsageKind, QuotaLimit[]> = {
  // A normal day is ~3–6 logs; the headroom covers retries and re-photographs.
  meal_parse: [
    { windowMs: HOUR_MS, max: 20 },
    { windowMs: DAY_MS, max: 60 },
  ],
  // Tier 3 is a short, bounded conversation (§2) — a few turns per episode.
  tier3_message: [
    { windowMs: HOUR_MS, max: 20 },
    { windowMs: DAY_MS, max: 40 },
  ],
};

/** Usage rows older than this are never needed for a decision. */
export const AI_USAGE_RETENTION_MS = 2 * DAY_MS;

export class AiQuotaExceededError extends Error {
  constructor(
    readonly kind: AiUsageKind,
    readonly retryAfterSeconds: number,
  ) {
    super('Too many requests right now. Try again in a bit.');
  }
}

export type QuotaDecision = { allowed: true } | { allowed: false; retryAfterSeconds: number };

/** Pure: may one more call happen, given the timestamps (ms) of recent calls? */
export function evaluateQuota(usedAt: number[], limits: QuotaLimit[], now: number): QuotaDecision {
  let retryAfterMs = 0;
  for (const limit of limits) {
    const inWindow = usedAt.filter((t) => t > now - limit.windowMs).sort((a, b) => a - b);
    if (inWindow.length >= limit.max) {
      // Room opens once enough of the oldest calls age out of the window.
      const freeing = inWindow[inWindow.length - limit.max]!;
      retryAfterMs = Math.max(retryAfterMs, freeing + limit.windowMs - now);
    }
  }
  return retryAfterMs > 0
    ? { allowed: false, retryAfterSeconds: Math.max(1, Math.ceil(retryAfterMs / 1000)) }
    : { allowed: true };
}

/**
 * Records one AI call for the user, or throws AiQuotaExceededError. A soft
 * limit: two simultaneous requests can both pass, which is fine for cost control.
 */
export async function consumeAiQuota(
  prisma: PrismaClient,
  userId: string,
  kind: AiUsageKind,
  now: Date = new Date(),
): Promise<void> {
  const limits = AI_QUOTAS[kind];
  const longest = Math.max(...limits.map((l) => l.windowMs));
  const rows = await prisma.aiUsage.findMany({
    where: { userId, kind, createdAt: { gt: new Date(now.getTime() - longest) } },
    select: { createdAt: true },
  });

  const decision = evaluateQuota(
    rows.map((r) => r.createdAt.getTime()),
    limits,
    now.getTime(),
  );
  if (!decision.allowed) throw new AiQuotaExceededError(kind, decision.retryAfterSeconds);

  await prisma.aiUsage.create({ data: { userId, kind, createdAt: now } });
}

/** Drops usage rows no decision will read again. Run from the daily cron. */
export async function pruneAiUsage(prisma: PrismaClient, now: Date = new Date()): Promise<number> {
  const { count } = await prisma.aiUsage.deleteMany({
    where: { createdAt: { lt: new Date(now.getTime() - AI_USAGE_RETENTION_MS) } },
  });
  return count;
}
