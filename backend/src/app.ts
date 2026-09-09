import cors from '@fastify/cors';
import sensible from '@fastify/sensible';
import Fastify, { type FastifyInstance } from 'fastify';
import { env, isDev } from './env.js';
import { cronRoutes } from './routes/cron.js';
import { healthRoutes } from './routes/health.js';

export async function buildApp(): Promise<FastifyInstance> {
  const app = Fastify({
    trustProxy: true,
    logger: isDev
      ? { level: 'debug', transport: { target: 'pino-pretty', options: { translateTime: 'HH:MM:ss' } } }
      : { level: env.NODE_ENV === 'test' ? 'silent' : 'info' },
  });

  await app.register(sensible);
  await app.register(cors, { origin: true });

  await app.register(healthRoutes);
  await app.register(cronRoutes, { prefix: '/api/cron' });

  return app;
}
