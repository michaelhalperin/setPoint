// Applies pending Prisma migrations during the Vercel build.
//
// - Only production deploys migrate. Preview deploys share the production
//   DATABASE_URL, so a branch build must never change the schema.
// - Migrations need a direct (non-pooled) connection. Use DIRECT_URL when set,
//   otherwise derive it by dropping "-pooler" from the Neon host.
// - Prisma's migrate advisory lock (P1002) is unreliable from Vercel→Neon even
//   when the lock is free, so we:
//     1. Skip migrate entirely when the DB is already caught up (common case).
//     2. Disable advisory locking when we do need to apply migrations.
// - A failed migration fails the build, so code never ships ahead of its schema.
import { existsSync, readdirSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';
import { setTimeout as sleep } from 'node:timers/promises';
import { neon } from '@neondatabase/serverless';

const MAX_ATTEMPTS = 3;
const RETRY_BASE_MS = 5_000;

if (process.env.VERCEL && process.env.VERCEL_ENV !== 'production') {
  console.log(`[migrate] skipping on ${process.env.VERCEL_ENV ?? 'unknown'} deploy`);
  process.exit(0);
}

const pooled = process.env.DATABASE_URL;
if (!pooled) {
  console.error('[migrate] DATABASE_URL is not set');
  process.exit(1);
}

function directUrl(url) {
  const parsed = new URL(url);
  if (parsed.hostname.endsWith('.neon.tech')) {
    parsed.hostname = parsed.hostname.replace('-pooler.', '.');
  }
  return parsed.toString();
}

function localMigrations() {
  const migrationsDir = join(dirname(fileURLToPath(import.meta.url)), '..', 'prisma', 'migrations');
  return readdirSync(migrationsDir, { withFileTypes: true })
    .filter((d) => d.isDirectory() && existsSync(join(migrationsDir, d.name, 'migration.sql')))
    .map((d) => d.name)
    .sort();
}

async function pendingMigrations(databaseUrl) {
  const local = localMigrations();
  const sql = neon(databaseUrl);
  let applied;
  try {
    const rows = await sql`
      SELECT migration_name
      FROM "_prisma_migrations"
      WHERE finished_at IS NOT NULL AND rolled_back_at IS NULL
    `;
    applied = new Set(rows.map((r) => r.migration_name));
  } catch (err) {
    // Fresh database (no _prisma_migrations yet) — treat everything as pending.
    console.warn(`[migrate] could not read migration history (${err.message}); assuming pending`);
    return local;
  }
  return local.filter((name) => !applied.has(name));
}

function runMigrate(url) {
  const result = spawnSync('prisma', ['migrate', 'deploy'], {
    encoding: 'utf8',
    env: {
      ...process.env,
      DATABASE_URL: url,
      // Vercel builds consistently hit P1002 waiting on this lock against Neon.
      // Only this production script migrates, and we already gate on pending work.
      PRISMA_SCHEMA_DISABLE_ADVISORY_LOCK: '1',
    },
  });
  const stdout = result.stdout ?? '';
  const stderr = result.stderr ?? '';
  if (stdout) process.stdout.write(stdout);
  if (stderr) process.stderr.write(stderr);
  return {
    status: result.status ?? 1,
    error: result.error,
  };
}

const url = process.env.DIRECT_URL || directUrl(pooled);

const pending = await pendingMigrations(pooled);
if (pending.length === 0) {
  console.log('[migrate] database already up to date; skipping migrate deploy');
  process.exit(0);
}

console.log(`[migrate] ${pending.length} pending: ${pending.join(', ')}`);

for (let attempt = 1; attempt <= MAX_ATTEMPTS; attempt++) {
  console.log(`[migrate] deploy attempt ${attempt}/${MAX_ATTEMPTS}`);
  const result = runMigrate(url);

  if (result.error) {
    console.error(`[migrate] failed to start prisma: ${result.error.message}`);
    process.exit(1);
  }

  if (result.status === 0) {
    process.exit(0);
  }

  if (attempt === MAX_ATTEMPTS) {
    process.exit(result.status);
  }

  const delayMs = RETRY_BASE_MS * attempt;
  console.warn(`[migrate] deploy failed; retrying in ${delayMs / 1000}s…`);
  await sleep(delayMs);
}

process.exit(1);
