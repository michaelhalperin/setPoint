import { neonConfig } from '@neondatabase/serverless';
import { PrismaNeon } from '@prisma/adapter-neon';
import { PrismaClient } from '@prisma/client';
import ws from 'ws';
import { env, isProd } from '../env.js';

// Neon's serverless driver needs a WebSocket implementation when running in Node.
neonConfig.webSocketConstructor = ws;

declare global {
  // eslint-disable-next-line no-var
  var __setpointPrisma__: PrismaClient | undefined;
}

let cached: PrismaClient | undefined = globalThis.__setpointPrisma__;

/**
 * Lazily builds the Prisma client so the server can boot without a database
 * configured. The first caller that actually needs the DB gets a clear error
 * if DATABASE_URL is unset.
 */
export function getPrisma(): PrismaClient {
  if (cached) return cached;

  if (!env.DATABASE_URL) {
    throw new Error(
      'DATABASE_URL is not set. Create a Neon project and add the pooled ' +
        'connection string to backend/.env (see .env.example).',
    );
  }

  const adapter = new PrismaNeon({ connectionString: env.DATABASE_URL });
  cached = new PrismaClient({
    adapter,
    log: isProd ? ['error'] : ['warn', 'error'],
  });

  if (!isProd) globalThis.__setpointPrisma__ = cached;
  return cached;
}
