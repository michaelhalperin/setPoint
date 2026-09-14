import cors from '@fastify/cors';
import sensible from '@fastify/sensible';
import Fastify, { type FastifyInstance, type FastifyRequest } from 'fastify';
import { ZodError } from 'zod';
import { AiQuotaExceededError } from './ai/quota.js';
import { getPrisma } from './db/client.js';
import { env } from './env.js';
import { postgresRateLimiter, type RateLimiter } from './http/rateLimit.js';
import { captureError, flushSentry, initSentry } from './observability/sentry.js';
import { UnderageError } from './onboarding/age.js';
import { UnhealthyTargetError } from './onboarding/targets.js';
import { accountRoutes } from './routes/account.js';
import { adminRoutes } from './routes/admin.js';
import { authRoutes } from './routes/auth.js';
import { biosignalRoutes } from './routes/biosignals.js';
import { calendarRoutes } from './routes/calendar.js';
import { checkInRoutes } from './routes/checkins.js';
import { cronRoutes } from './routes/cron.js';
import { dashboardRoutes } from './routes/dashboard.js';
import { healthRoutes } from './routes/health.js';
import { legalRoutes } from './routes/legal.js';
import { mealRoutes } from './routes/meals.js';
import { foodRoutes } from './routes/foods.js';
import { pushTokenRoutes } from './routes/pushTokens.js';
import { savedMealRoutes } from './routes/savedMeals.js';
import { weightRoutes } from './routes/weight.js';

const AUTH_LIMIT_PER_MINUTE = 40;

export type BuildAppOptions = {
  /** Defaults to the shared Postgres limiter; off in tests so they never touch a real database. */
  authRateLimiter?: RateLimiter | null;
};

export async function buildApp(options: BuildAppOptions = {}): Promise<FastifyInstance> {
  const authRateLimiter =
    options.authRateLimiter !== undefined
      ? options.authRateLimiter
      : env.NODE_ENV === 'test'
        ? null
        : postgresRateLimiter(getPrisma);
  initSentry();

  // pino-pretty (a devDependency, loaded in a worker thread) is opt-in via
  // LOG_PRETTY so it can never break a serverless bundle where it isn't traced.
  const prettyLogs = process.env.LOG_PRETTY === 'true';
  const app = Fastify({
    trustProxy: true,
    bodyLimit: 1_000_000,
    logger:
      env.NODE_ENV === 'test'
        ? { level: 'silent' }
        : prettyLogs
          ? { level: 'debug', transport: { target: 'pino-pretty', options: { translateTime: 'HH:MM:ss' } } }
          : { level: 'info' },
  });

  await app.register(sensible);
  await app.register(cors, { origin: true });

  // Sign-in endpoints: 40 attempts a minute per client IP, counted in Postgres
  // so the limit holds across serverless instances. Fails open — a database
  // hiccup must not lock everyone out of signing in.
  if (authRateLimiter) {
    app.addHook('onRequest', async (req, reply) => {
      if (!req.url.startsWith('/api/auth')) return;
      try {
        const decision = await authRateLimiter(`auth:${req.ip}`, AUTH_LIMIT_PER_MINUTE, 60);
        if (!decision.allowed) {
          return reply
            .status(429)
            .header('retry-after', String(decision.retryAfterSeconds))
            .send({ error: 'Too Many Requests', message: 'Too many sign-in attempts. Try again in a minute.' });
        }
      } catch (err) {
        req.log.warn({ err }, 'auth rate limit unavailable — allowing request');
      }
    });
  }

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
    if (err instanceof UnderageError) {
      return reply.status(403).send({ error: 'Forbidden', message: err.message });
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
  await app.register(savedMealRoutes, { prefix: '/api/saved-meals' });
  await app.register(foodRoutes, { prefix: '/api/foods' });
  await app.register(calendarRoutes, { prefix: '/api/calendar' });
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
