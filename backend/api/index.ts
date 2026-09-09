import type { IncomingMessage, ServerResponse } from 'node:http';
import { buildApp } from '../src/app.js';

// Vercel reuses the module across invocations on a warm lambda, so build once.
let appPromise: ReturnType<typeof buildApp> | undefined;

export default async function handler(req: IncomingMessage, res: ServerResponse): Promise<void> {
  appPromise ??= buildApp();
  const app = await appPromise;
  await app.ready();
  app.server.emit('request', req, res);
}
