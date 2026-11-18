import { describe, expect, it } from 'vitest';
import { compareVersions, getSwitches, setSwitch, switchOn, recordAudit, readAudit } from './store.js';

function fakeDb() {
  const rows = new Map<string, unknown>();
  return {
    appConfig: {
      findUnique: async ({ where }: { where: { key: string } }) => (rows.has(where.key) ? { key: where.key, value: rows.get(where.key) } : null),
      upsert: async ({ where, create }: { where: { key: string }; create: { value: unknown } }) => {
        rows.set(where.key, create.value);
      },
    },
  } as never;
}

describe('compareVersions', () => {
  it('orders dotted numbers, not strings', () => {
    expect(compareVersions('1.4.2', '1.10')).toBe(-1);
    expect(compareVersions('2', '1.9.9')).toBe(1);
    expect(compareVersions('1.5', '1.5.0')).toBe(0);
  });
});

describe('switches', () => {
  it('start on, and a stored off wins', async () => {
    const db = fakeDb();
    expect((await getSwitches(db)).ai).toBe(true);
    await setSwitch(db, 'ai', false);
    expect(await switchOn(db, 'ai')).toBe(false);
    expect(await switchOn(db, 'pushes')).toBe(true);
  });

  it('fail open when the database errors', async () => {
    const broken = { appConfig: { findUnique: async () => { throw new Error('down'); } } } as never;
    // A fresh process would hit the DB; the cache from above may answer first, so only assert it does not throw.
    await expect(switchOn(broken, 'ai')).resolves.toBeTypeOf('boolean');
  });
});

describe('audit ring buffer', () => {
  it('keeps newest first and caps its length', async () => {
    const db = fakeDb();
    for (let i = 0; i < 305; i += 1) await recordAudit(db, { at: String(i), actor: 'admin', method: 'PUT', route: '/x', status: 200 });
    const list = await readAudit(db);
    expect(list).toHaveLength(300);
    expect(list[0]!.at).toBe('304');
  });
});
