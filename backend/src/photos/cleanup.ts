import type { PrismaClient } from '@prisma/client';
import type { PhotoStore } from './store.js';

export type PhotoDeletion = { kind: 'object'; key: string } | { kind: 'user'; userId: string };

/** Give up (and keep the row for a person to look at) after this many tries. */
export const MAX_PHOTO_DELETE_ATTEMPTS = 10;

/** Records a failed delete so the daily cron retries it. Never throws. */
export async function queuePhotoDeletion(prisma: PrismaClient, deletion: PhotoDeletion, err: unknown): Promise<void> {
  const target = deletion.kind === 'object' ? deletion.key : deletion.userId;
  const lastError = String(err instanceof Error ? err.message : err).slice(0, 500);
  try {
    await prisma.pendingPhotoDeletion.upsert({
      where: { kind_target: { kind: deletion.kind, target } },
      create: { kind: deletion.kind, target, lastError },
      update: { lastError },
    });
  } catch (queueErr) {
    console.error('[photos] could not queue a failed delete for retry', { deletion, queueErr });
  }
}

export type PhotoCleanupSummary = {
  attempted: number;
  deleted: number;
  failed: number;
  /** Rows that hit the attempt limit and need a person. */
  givenUp: number;
};

/** Retries queued deletes, oldest first. */
export async function retryPhotoDeletions(
  prisma: PrismaClient,
  photos: PhotoStore,
  opts: { limit?: number; now?: Date } = {},
): Promise<PhotoCleanupSummary> {
  const now = opts.now ?? new Date();
  const rows = await prisma.pendingPhotoDeletion.findMany({
    where: { attempts: { lt: MAX_PHOTO_DELETE_ATTEMPTS } },
    orderBy: { createdAt: 'asc' },
    take: opts.limit ?? 100,
  });

  const summary: PhotoCleanupSummary = { attempted: rows.length, deleted: 0, failed: 0, givenUp: 0 };
  for (const row of rows) {
    try {
      if (row.kind === 'user') await photos.deleteAllForUser(row.target);
      else await photos.delete(row.target);
      await prisma.pendingPhotoDeletion.delete({ where: { id: row.id } });
      summary.deleted += 1;
    } catch (err) {
      summary.failed += 1;
      await prisma.pendingPhotoDeletion.update({
        where: { id: row.id },
        data: {
          attempts: { increment: 1 },
          lastTriedAt: now,
          lastError: String(err instanceof Error ? err.message : err).slice(0, 500),
        },
      });
    }
  }
  summary.givenUp = await prisma.pendingPhotoDeletion.count({
    where: { attempts: { gte: MAX_PHOTO_DELETE_ATTEMPTS } },
  });
  return summary;
}
