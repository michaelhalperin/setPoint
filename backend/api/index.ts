import type { IncomingMessage, ServerResponse } from 'node:http';

// Vercel reuses the module across invocations on a warm lambda, so build once.
let appPromise: Promise<import('fastify').FastifyInstance> | undefined;

export default async function handler(req: IncomingMessage, res: ServerResponse): Promise<void> {
  // Answer the bare root directly — Vercel routes "/" here and something in the
  // emit('request') path chokes on it. Everything real is under /api.
  let pathname = req.url ?? '/';
  try {
    pathname = new URL(req.url ?? '/', 'http://localhost').pathname;
  } catch {
    /* keep raw */
  }
  if (pathname === '/' || pathname === '') {
    res.statusCode = 200;
    res.setHeader('content-type', 'application/json');
    res.end(JSON.stringify({ name: 'SetPoint API', status: 'ok', api: '/api/health' }));
    return;
  }

  try {
    if (!appPromise) {
      // Import lazily so a bootstrap error (bad env, missing generated client)
      // is caught here and reported, not swallowed as FUNCTION_INVOCATION_FAILED.
      appPromise = import('../src/app.js').then((m) => m.buildApp());
    }
    const app = await appPromise;
    await app.ready();
    app.server.emit('request', req, res);
  } catch (err) {
    appPromise = undefined; // let the next request retry
    const message = err instanceof Error ? err.message : String(err);
    console.error('bootstrap failed:', err);
    try {
      // Best effort: if the env itself is what's broken, this import fails too.
      const sentry = await import('../src/observability/sentry.js');
      sentry.initSentry();
      sentry.captureError(err, { tags: { area: 'bootstrap' } });
      await sentry.flushSentry();
    } catch {
      /* nothing to report with */
    }
    res.statusCode = 500;
    res.setHeader('content-type', 'application/json');
    res.end(JSON.stringify({ error: 'Bootstrap failed', message }));
  }
}
