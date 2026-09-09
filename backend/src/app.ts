import cors from '@fastify/cors';
import sensible from '@fastify/sensible';
import Fastify, { type FastifyInstance } from 'fastify';
import { ZodError } from 'zod';
import { env } from './env.js';
import { accountRoutes } from './routes/account.js';
import { authRoutes } from './routes/auth.js';
import { checkInRoutes } from './routes/checkins.js';
import { cronRoutes } from './routes/cron.js';
import { dashboardRoutes } from './routes/dashboard.js';
import { healthRoutes } from './routes/health.js';
import { mealRoutes } from './routes/meals.js';

export async function buildApp(): Promise<FastifyInstance> {
  // pino-pretty (a devDependency, loaded in a worker thread) is opt-in via
  // LOG_PRETTY so it can never break a serverless bundle where it isn't traced.
  const prettyLogs = process.env.LOG_PRETTY === 'true';
  const app = Fastify({
    trustProxy: true,
    logger:
      env.NODE_ENV === 'test'
        ? { level: 'silent' }
        : prettyLogs
          ? { level: 'debug', transport: { target: 'pino-pretty', options: { translateTime: 'HH:MM:ss' } } }
          : { level: 'info' },
  });

  await app.register(sensible);
  await app.register(cors, { origin: true });

  app.setErrorHandler((err: unknown, req, reply) => {
    if (err instanceof ZodError) {
      return reply.status(400).send({ error: 'Bad Request', message: 'validation failed', issues: err.issues });
    }
    // Deliberate errors from `app.httpErrors.*` carry a statusCode; honour it and
    // expose their message. Everything else is an unexpected 500.
    const e = err as { statusCode?: unknown; name?: string; message?: string };
    if (typeof e.statusCode === 'number' && e.statusCode >= 400 && e.statusCode < 600) {
      if (e.statusCode >= 500) req.log.warn(err as Error);
      return reply.status(e.statusCode).send({ error: e.name ?? 'Error', message: e.message ?? '' });
    }
    req.log.error(err as Error);
    return reply.status(500).send({ error: 'Internal Server Error' });
  });

  await app.register(healthRoutes);
  await app.register(authRoutes, { prefix: '/api/auth' });
  await app.register(mealRoutes, { prefix: '/api/meals' });
  await app.register(checkInRoutes, { prefix: '/api/checkins' });
  await app.register(accountRoutes, { prefix: '/api' });
  await app.register(dashboardRoutes, { prefix: '/api' });
  await app.register(cronRoutes, { prefix: '/api/cron' });

  return app;
}
