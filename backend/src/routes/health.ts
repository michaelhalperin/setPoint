import type { FastifyInstance } from 'fastify';
import { getAnthropic } from '../ai/client.js';
import { getPrisma } from '../db/client.js';

export async function healthRoutes(app: FastifyInstance): Promise<void> {
  const banner = async () => ({ name: 'SetPoint API', status: 'ok', docs: 'see backend/README.md' });
  app.get('/', banner);
  app.get('/api', banner);

  app.get('/api/health', async () => {
    let db: 'up' | 'down' = 'down';
    try {
      await getPrisma().$queryRaw`SELECT 1`;
      db = 'up';
    } catch (err) {
      app.log.warn(`health: database check failed — ${(err as Error).message}`);
    }

    return {
      status: db === 'up' ? 'ok' : 'degraded',
      db,
      // Whether an ANTHROPIC_API_KEY is configured (does not call the API).
      // "fallback" means AI features run on their deterministic paths.
      ai: getAnthropic() ? 'configured' : 'fallback',
      ts: new Date().toISOString(),
    };
  });
}
