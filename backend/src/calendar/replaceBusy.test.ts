import { describe, expect, it } from 'vitest';
import type { PrismaClient } from '@prisma/client';
import { replaceBusyWindow } from './replaceBusy.js';

type Row = { userId: string; start: Date; end: Date };

function fakePrisma(existing: Row[] = []) {
  const rows = [...existing];
  return {
    __rows: rows,
    calendarBusyBlock: {
      deleteMany: async ({ where }: { where: { userId: string; start: { lt: Date }; end: { gt: Date } } }) => {
        const before = rows.length;
        for (let i = rows.length - 1; i >= 0; i -= 1) {
          const row = rows[i]!;
          if (row.userId === where.userId && row.start < where.start.lt && row.end > where.end.gt) {
            rows.splice(i, 1);
          }
        }
        return { count: before - rows.length };
      },
      createMany: async ({ data }: { data: Row[] }) => {
        rows.push(...data);
        return { count: data.length };
      },
    },
  } as unknown as PrismaClient & { __rows: Row[] };
}

describe('replaceBusyWindow', () => {
  it('replaces overlapping blocks and stores only start/end', async () => {
    const from = new Date('2026-09-14T12:00:00Z');
    const to = new Date('2026-09-16T00:00:00Z');
    const prisma = fakePrisma([
      { userId: 'u1', start: new Date('2026-09-14T13:00:00Z'), end: new Date('2026-09-14T15:00:00Z') },
    ]);
    const stored = await replaceBusyWindow(prisma, 'u1', from, to, [
      { start: new Date('2026-09-14T16:00:00Z'), end: new Date('2026-09-14T18:00:00Z') },
    ]);
    expect(stored).toBe(1);
    expect((prisma as unknown as { __rows: Row[] }).__rows).toEqual([
      { userId: 'u1', start: new Date('2026-09-14T16:00:00Z'), end: new Date('2026-09-14T18:00:00Z') },
    ]);
  });
});
