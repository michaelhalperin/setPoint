import type { IncomingMessage, ServerResponse } from 'node:http';

// Vercel reuses the module across invocations on a warm lambda, so build once.
let appPromise: Promise<import('fastify').FastifyInstance> | undefined;

export default async function handler(req: IncomingMessage, res: ServerResponse): Promise<void> {
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
    res.statusCode = 500;
    res.setHeader('content-type', 'application/json');
    res.end(JSON.stringify({ error: 'Bootstrap failed', message }));
  }
}
