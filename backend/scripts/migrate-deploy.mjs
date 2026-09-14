// Applies pending Prisma migrations during the Vercel build.
//
// - Only production deploys migrate. Preview deploys share the production
//   DATABASE_URL, so a branch build must never change the schema.
// - Migrations need a direct (non-pooled) connection: Prisma takes a session
//   advisory lock that Neon's transaction-mode pooler can't hold. Use
//   DIRECT_URL when set, otherwise derive it by dropping "-pooler" from the
//   Neon host.
// - P1002 (advisory lock timeout) is retried — concurrent deploys or a
//   briefly stuck Neon session are common; the lock is acquired before any
//   migration runs, so a retry is safe.
// - A failed migration fails the build, so code never ships ahead of its schema.
import { spawnSync } from 'node:child_process';
import { setTimeout as sleep } from 'node:timers/promises';

const MAX_ATTEMPTS = 5;
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

function isAdvisoryLockTimeout(output) {
  return /\bP1002\b/.test(output) || /advisory lock/i.test(output);
}

function runMigrate(url) {
  const result = spawnSync('prisma', ['migrate', 'deploy'], {
    encoding: 'utf8',
    env: { ...process.env, DATABASE_URL: url },
  });
  const stdout = result.stdout ?? '';
  const stderr = result.stderr ?? '';
  if (stdout) process.stdout.write(stdout);
  if (stderr) process.stderr.write(stderr);
  return {
    status: result.status ?? 1,
    output: `${stdout}\n${stderr}`,
    error: result.error,
  };
}

const url = process.env.DIRECT_URL || directUrl(pooled);

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

  const retryable = isAdvisoryLockTimeout(result.output);
  if (!retryable || attempt === MAX_ATTEMPTS) {
    process.exit(result.status);
  }

  const delayMs = RETRY_BASE_MS * attempt;
  console.warn(
    `[migrate] advisory lock timeout (P1002); retrying in ${delayMs / 1000}s…`,
  );
  await sleep(delayMs);
}

process.exit(1);
