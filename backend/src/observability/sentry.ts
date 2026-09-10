import * as Sentry from '@sentry/node';
import { env } from '../env.js';

/**
 * Error reporting. Everything here is a no-op until SENTRY_DSN is set, so local
 * runs and tests never send anything.
 *
 * Privacy (§4): no request bodies (meal text, health values), no auth or secret
 * headers, no IPs. The only identifier attached is the internal user id.
 */
let started = false;

const SCRUBBED_HEADERS = ['authorization', 'cookie', 'x-session-token', 'x-cron-secret', 'x-admin-secret'];

export function initSentry(): boolean {
  if (started) return true;
  if (!env.SENTRY_DSN) return false;

  Sentry.init({
    dsn: env.SENTRY_DSN,
    environment: env.SENTRY_ENVIRONMENT || env.NODE_ENV,
    release: process.env.VERCEL_GIT_COMMIT_SHA,
    sendDefaultPii: false,
    tracesSampleRate: 0,
    beforeSend(event) {
      if (event.request) {
        delete event.request.data;
        delete event.request.cookies;
        delete event.request.query_string;
        const headers = event.request.headers;
        if (headers) for (const name of SCRUBBED_HEADERS) delete headers[name];
      }
      if (event.user) event.user = { id: event.user.id };
      return event;
    },
  });
  started = true;
  return true;
}

export type ErrorContext = {
  userId?: string;
  tags?: Record<string, string>;
  extra?: Record<string, unknown>;
};

export function captureError(err: unknown, context: ErrorContext = {}): void {
  if (!started) return;
  Sentry.withScope((scope) => {
    if (context.userId) scope.setUser({ id: context.userId });
    for (const [key, value] of Object.entries(context.tags ?? {})) scope.setTag(key, value);
    if (context.extra) scope.setExtras(context.extra);
    Sentry.captureException(err);
  });
}

/** A serverless function is frozen once it responds — send queued events first. */
export async function flushSentry(timeoutMs = 2000): Promise<void> {
  if (!started) return;
  await Sentry.flush(timeoutMs);
}
