import type { Prisma, PrismaClient } from '@prisma/client';
import { env } from '../env.js';

/**
 * Everything the admin control room keeps lives in AppConfig rows, one key each, so it needs no
 * migration: switches, the app-version gate, the maintenance notice, alert rules, test accounts,
 * and two short ring buffers (admin actions, server errors).
 */
type Db = Pick<PrismaClient, 'appConfig'>;

export async function readConfig<T>(db: Db, key: string, fallback: T): Promise<T> {
  const row = await db.appConfig.findUnique({ where: { key } });
  return row ? (row.value as T) : fallback;
}

export async function writeConfig(db: Db, key: string, value: unknown): Promise<void> {
  const json = value as Prisma.InputJsonValue;
  await db.appConfig.upsert({ where: { key }, create: { key, value: json }, update: { value: json } });
}

// ── Kill switches ───────────────────────────────────────────────────────────

export const SWITCHES = {
  ai: { label: 'AI meal parsing + coach', hint: 'Off: the app falls back to manual entry.' },
  experts: { label: 'Expert chats', hint: 'Diet and training experts. Safety trips are still logged.' },
  pushes: { label: 'Send pushes', hint: 'Off: nothing is sent; the queue keeps filling.' },
  scheduler: { label: 'Scheduler (cron jobs)', hint: 'Off: score and settle skip their runs.' },
  invite_only: { label: 'Invite-only signups', hint: 'On: new accounts need a live invite code.' },
} as const;

export type SwitchKey = keyof typeof SWITCHES;
export const isSwitchKey = (k: string): k is SwitchKey => Object.prototype.hasOwnProperty.call(SWITCHES, k);
export type Switches = Record<SwitchKey, boolean>;

const SWITCHES_KEY = 'admin:switches';

function defaults(): Switches {
  return { ai: true, experts: true, pushes: true, scheduler: true, invite_only: env.INVITE_ONLY === 'true' };
}

let cache: { at: number; value: Switches } | null = null;
/** Sync mirror of the invite-only switch, for code that can't await. Refreshed whenever switches load. */
let inviteOnlyMirror: boolean | null = null;
export const inviteOnlyMirrored = (): boolean | null => inviteOnlyMirror;
const CACHE_MS = 20_000;

export async function getSwitches(db: Db): Promise<Switches> {
  if (cache && Date.now() - cache.at < CACHE_MS) return cache.value;
  const stored = await readConfig<Partial<Switches>>(db, SWITCHES_KEY, {});
  const value = { ...defaults(), ...stored };
  cache = { at: Date.now(), value };
  inviteOnlyMirror = value.invite_only;
  return value;
}

export async function setSwitch(db: Db, key: SwitchKey, on: boolean): Promise<Switches> {
  const stored = await readConfig<Partial<Switches>>(db, SWITCHES_KEY, {});
  await writeConfig(db, SWITCHES_KEY, { ...stored, [key]: on });
  cache = null;
  return getSwitches(db);
}

/** Fails open: a database hiccup never turns a feature off by itself. */
export async function switchOn(db: Db, key: SwitchKey): Promise<boolean> {
  try {
    return (await getSwitches(db))[key];
  } catch {
    return defaults()[key];
  }
}

// ── App version gate + maintenance notice ───────────────────────────────────

export type VersionGate = { min: string | null; latest: string | null };
export type Maintenance = { active: boolean; en: string; he: string; updatedAt: string | null };

export const readVersionGate = (db: Db) => readConfig<VersionGate>(db, 'admin:version', { min: null, latest: null });
export const readMaintenance = (db: Db) =>
  readConfig<Maintenance>(db, 'admin:maintenance', { active: false, en: '', he: '', updatedAt: null });

export const VERSION_RE = /^\d+(\.\d+){0,2}$/;

/** -1 / 0 / 1 for dotted numeric versions: "1.4.2" < "1.10". */
export function compareVersions(a: string, b: string): number {
  const pa = a.split('.').map(Number);
  const pb = b.split('.').map(Number);
  for (let i = 0; i < Math.max(pa.length, pb.length); i += 1) {
    const d = (pa[i] ?? 0) - (pb[i] ?? 0);
    if (d !== 0) return d < 0 ? -1 : 1;
  }
  return 0;
}

// ── Test accounts ───────────────────────────────────────────────────────────

const TEST_KEY = 'admin:test-accounts';
export const readTestAccounts = (db: Db) => readConfig<string[]>(db, TEST_KEY, []);
export async function setTestAccount(db: Db, userId: string, on: boolean): Promise<string[]> {
  const ids = new Set(await readTestAccounts(db));
  if (on) ids.add(userId);
  else ids.delete(userId);
  const next = [...ids];
  await writeConfig(db, TEST_KEY, next);
  return next;
}

// ── Alert rules ─────────────────────────────────────────────────────────────

export type AlertRules = {
  cronMissed: { on: boolean };
  pushFailure: { on: boolean; pct: number };
  aiSpend: { on: boolean; usd: number };
  serverErrors: { on: boolean; count: number };
  safetyTrip: { on: boolean };
};
export const DEFAULT_ALERT_RULES: AlertRules = {
  cronMissed: { on: true },
  pushFailure: { on: true, pct: 10 },
  aiSpend: { on: true, usd: 5 },
  serverErrors: { on: false, count: 5 },
  safetyTrip: { on: true },
};
export const readAlertRules = async (db: Db): Promise<AlertRules> => ({
  ...DEFAULT_ALERT_RULES,
  ...(await readConfig<Partial<AlertRules>>(db, 'admin:alert-rules', {})),
});

// ── Ring buffers: admin actions and server errors ──────────────────────────

export type AuditEntry = { at: string; actor: string; method: string; route: string; status: number };
export type ErrorEntry = { at: string; method: string; route: string; status: number; message: string };

async function push<T>(db: Db, key: string, entry: T, cap: number): Promise<void> {
  const list = await readConfig<T[]>(db, key, []);
  list.unshift(entry);
  await writeConfig(db, key, list.slice(0, cap));
}

export const recordAudit = (db: Db, e: AuditEntry) => push(db, 'admin:audit', e, 300);
export const recordError = (db: Db, e: ErrorEntry) => push(db, 'admin:errors', e, 100);
export const readAudit = (db: Db) => readConfig<AuditEntry[]>(db, 'admin:audit', []);
export const readErrors = (db: Db) => readConfig<ErrorEntry[]>(db, 'admin:errors', []);
