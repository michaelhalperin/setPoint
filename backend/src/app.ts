import cors from '@fastify/cors';
import sensible from '@fastify/sensible';
import Fastify, { type FastifyInstance, type FastifyRequest } from 'fastify';
import { ZodError } from 'zod';
import { AiQuotaExceededError } from './ai/quota.js';
import { env } from './env.js';
import { captureError, flushSentry, initSentry } from './observability/sentry.js';
import { UnhealthyTargetError } from './onboarding/targets.js';
import { accountRoutes } from './routes/account.js';
import { adminRoutes } from './routes/admin.js';
import { authRoutes } from './routes/auth.js';
import { biosignalRoutes } from './routes/biosignals.js';
import { checkInRoutes } from './routes/checkins.js';
import { cronRoutes } from './routes/cron.js';
import { dashboardRoutes } from './routes/dashboard.js';
import { healthRoutes } from './routes/health.js';
import { legalRoutes } from './routes/legal.js';
import { mealRoutes } from './routes/meals.js';
import { pushTokenRoutes } from './routes/pushTokens.js';
import { weightRoutes } from './routes/weight.js';

export async function buildApp(): Promise<FastifyInstance> {
  initSentry();

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

  app.setErrorHandler(async (err: unknown, req, reply) => {
    if (err instanceof ZodError) {
      return reply.status(400).send({ error: 'Bad Request', message: 'validation failed', issues: err.issues });
    }
    if (err instanceof AiQuotaExceededError) {
      return reply
        .status(429)
        .header('retry-after', String(err.retryAfterSeconds))
        .send({ error: 'Too Many Requests', message: err.message });
    }
    if (err instanceof UnhealthyTargetError) {
      return reply
        .status(400)
        .send({ error: 'Bad Request', message: err.message, minWeightKg: err.minWeightKg });
    }
    // Deliberate errors from `app.httpErrors.*` carry a statusCode; honour it and
    // expose their message. Everything else is an unexpected 500.
    const e = err as { statusCode?: unknown; name?: string; message?: string };
    if (typeof e.statusCode === 'number' && e.statusCode >= 400 && e.statusCode < 600) {
      if (e.statusCode >= 500) {
        req.log.warn(err as Error);
        await reportServerError(err, req);
      }
      return reply.status(e.statusCode).send({ error: e.name ?? 'Error', message: e.message ?? '' });
    }
    req.log.error(err as Error);
    await reportServerError(err, req);
    return reply.status(500).send({ error: 'Internal Server Error' });
  });

  await app.register(healthRoutes);
  await app.register(legalRoutes);
  await app.register(authRoutes, { prefix: '/api/auth' });
  await app.register(mealRoutes, { prefix: '/api/meals' });
  await app.register(checkInRoutes, { prefix: '/api/checkins' });
  await app.register(biosignalRoutes, { prefix: '/api/biosignals' });
  await app.register(pushTokenRoutes, { prefix: '/api/push-tokens' });
  await app.register(weightRoutes, { prefix: '/api/weight' });
  await app.register(accountRoutes, { prefix: '/api' });
  await app.register(dashboardRoutes, { prefix: '/api' });
  await app.register(adminRoutes, { prefix: '/api/admin' });
  await app.register(cronRoutes, { prefix: '/api/cron' });

  return app;
}

/** Sends a server error to Sentry (a no-op without a DSN) before the function freezes. */
async function reportServerError(err: unknown, req: FastifyRequest): Promise<void> {
  captureError(err, {
    userId: (req as { userId?: string }).userId,
    tags: { route: req.routeOptions.url ?? 'unmatched', method: req.method },
  });
  await flushSentry();
}
