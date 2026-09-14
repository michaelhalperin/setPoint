// Applies pending Prisma migrations during the Vercel build.
//
// - Only production deploys migrate. Preview deploys share the production
//   DATABASE_URL, so a branch build must never change the schema.
// - Migrations need a direct (non-pooled) connection: Prisma takes a session
//   advisory lock that Neon's transaction-mode pooler can't hold. Use
//   DIRECT_URL when set, otherwise derive it by dropping "-pooler" from the
//   Neon host.
// - A failed migration fails the build, so code never ships ahead of its schema.
import { spawnSync } from 'node:child_process';

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

const url = process.env.DIRECT_URL || directUrl(pooled);
const result = spawnSync('prisma', ['migrate', 'deploy'], {
  stdio: 'inherit',
  env: { ...process.env, DATABASE_URL: url },
});
process.exit(result.status ?? 1);
