import type { PrismaClient } from '@prisma/client';
import { describe, expect, it, vi } from 'vitest';
import { MAX_PHOTO_DELETE_ATTEMPTS, queuePhotoDeletion, retryPhotoDeletions } from './cleanup.js';
import type { PhotoStore } from './store.js';

type Row = { id: string; kind: string; target: string; attempts: number; lastError: string | null; createdAt: Date };

function fakeDb() {
  const rows: Row[] = [];
  let seq = 0;
  const db = {
    pendingPhotoDeletion: {
      upsert: async ({ where, create, update }: { where: { kind_target: { kind: string; target: string } }; create: Partial<Row>; update: Partial<Row> }) => {
        const row = rows.find((r) => r.kind === where.kind_target.kind && r.target === where.kind_target.target);
        if (row) return Object.assign(row, update);
        const created = { id: `p${(seq += 1)}`, attempts: 0, lastError: null, createdAt: new Date(seq), ...create } as Row;
        rows.push(created);
        return created;
      },
      findMany: async () => rows.filter((r) => r.attempts < MAX_PHOTO_DELETE_ATTEMPTS),
      delete: async ({ where }: { where: { id: string } }) => rows.splice(rows.findIndex((r) => r.id === where.id), 1),
      update: async ({ where, data }: { where: { id: string }; data: { attempts: { increment: number }; lastError: string } }) => {
        const row = rows.find((r) => r.id === where.id)!;
        row.attempts += data.attempts.increment;
        row.lastError = data.lastError;
        return row;
      },
      count: async () => rows.filter((r) => r.attempts >= MAX_PHOTO_DELETE_ATTEMPTS).length,
    },
  };
  return { prisma: db as unknown as PrismaClient, rows };
}

const store = (over: Partial<PhotoStore> = {}): PhotoStore => ({
  put: vi.fn(),
  signedUrl: vi.fn(),
  delete: vi.fn(async () => {}),
  deleteAllForUser: vi.fn(async () => 0),
  ...over,
});

describe('photo cleanup', () => {
  it('queues each failed delete once and retries it until it succeeds', async () => {
    const { prisma, rows } = fakeDb();
    await queuePhotoDeletion(prisma, { kind: 'object', key: 'meals/u1/a.jpg' }, new Error('r2 down'));
    await queuePhotoDeletion(prisma, { kind: 'object', key: 'meals/u1/a.jpg' }, new Error('r2 down again'));
    await queuePhotoDeletion(prisma, { kind: 'user', userId: 'u2' }, new Error('r2 down'));
    expect(rows).toHaveLength(2);

    const photos = store();
    const summary = await retryPhotoDeletions(prisma, photos);
    expect(photos.delete).toHaveBeenCalledWith('meals/u1/a.jpg');
    expect(photos.deleteAllForUser).toHaveBeenCalledWith('u2');
    expect(summary).toEqual({ attempted: 2, deleted: 2, failed: 0, givenUp: 0 });
    expect(rows).toHaveLength(0);
  });

  it('keeps failures for the next run and gives up after the attempt limit', async () => {
    const { prisma, rows } = fakeDb();
    await queuePhotoDeletion(prisma, { kind: 'object', key: 'meals/u1/b.jpg' }, 'x');
    const broken = store({ delete: vi.fn(async () => { throw new Error('still down'); }) });

    for (let i = 0; i < MAX_PHOTO_DELETE_ATTEMPTS; i += 1) await retryPhotoDeletions(prisma, broken);
    expect(rows[0]).toMatchObject({ attempts: MAX_PHOTO_DELETE_ATTEMPTS, lastError: 'still down' });

    const after = await retryPhotoDeletions(prisma, broken);
    expect(after).toEqual({ attempted: 0, deleted: 0, failed: 0, givenUp: 1 });
  });

  it('never throws when the queue itself is unavailable', async () => {
    await expect(
      queuePhotoDeletion({} as PrismaClient, { kind: 'object', key: 'k' }, new Error('x')),
    ).resolves.toBeUndefined();
  });
});
