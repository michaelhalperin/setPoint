import type { FastifyRequest } from 'fastify';
import { ZodError } from 'zod';
import { AiQuotaExceededError } from '../ai/quota.js';
import { getPrisma } from '../db/client.js';
import { EmptyMealError, MealParsingUnavailableError } from '../meals/logMeal.js';
import { track, type EventName } from './events.js';

const SKIP_STATUS = new Set([401, 403]);
const SKIP_PATHS = ['/admin', '/api/admin', '/api/cron', '/api/events', '/api/health', '/health', '/privacy', '/terms'];

/**
 * Turns a Fastify route pattern into a short analytics code — slashes aren't
 * allowed in event props.
 */
export function routeCode(url: string | undefined): string {
  return (url ?? 'unmatched')
    .replace(/^\//, '')
    .replace(/[/:]/g, '.')
    .replace(/\.+/g, '.')
    .replace(/^\.|\.$/g, '')
    .slice(0, 40) || 'unmatched';
}

export function mealSourceFromBody(body: unknown): string {
  if (!body || typeof body !== 'object' || Array.isArray(body)) return 'UNKNOWN';
  const b = body as Record<string, unknown>;
  if (b.image) return 'PHOTO';
  if (b.savedMealId) return 'SAVED';
  if (b.barcode) return 'BARCODE';
  if (b.catalogId) return 'CATALOG';
  if (b.prescriptionId) return 'PRESCRIPTION';
  if (b.macros) return 'MANUAL';
  if (b.text) return 'TEXT';
  return 'UNKNOWN';
}

export function failReason(err: unknown, status?: number): string {
  if (err instanceof ZodError) return 'invalid';
  if (err instanceof EmptyMealError) return 'empty';
  if (err instanceof MealParsingUnavailableError) return 'parse';
  if (err instanceof AiQuotaExceededError) return 'quota';
  if (status === 429) return 'quota';
  if (status === 503) return 'parse';
  if (status === 409) return 'conflict';
  if (status === 404) return 'not_found';
  if (status === 400) return 'bad_request';
  if (status !== undefined && status >= 500) return 'server';
  return 'unknown';
}

function requestPath(req: FastifyRequest): string {
  return (req.url ?? '').split('?')[0] ?? '';
}

function shouldSkip(req: FastifyRequest, status: number): boolean {
  if (SKIP_STATUS.has(status)) return true;
  const path = requestPath(req);
  const route = req.routeOptions.url ?? path;
  return SKIP_PATHS.some((p) => path.startsWith(p) || route.startsWith(p));
}

/**
 * Records a failed API call for the owner dashboard. Meal log failures are
 * recorded on the meals route (where we still have the error class); this
 * catches 5xx everywhere else, plus failed check-ins and weigh-ins.
 */
export async function trackHttpFailure(req: FastifyRequest, err: unknown, status: number): Promise<void> {
  if (shouldSkip(req, status)) return;
  const path = requestPath(req);
  const userId = (req as { userId?: string }).userId ?? null;
  const prisma = getPrisma();
  const reason = failReason(err, status);
  const route = routeCode(req.routeOptions.url ?? path);
  const method = req.method.toUpperCase();

  if (method === 'POST' && (path === '/api/meals' || path === '/api/meals/')) {
    return;
  }

  let name: EventName | null = null;
  if (method === 'POST' && path.startsWith('/api/checkins')) name = 'check_in_failed';
  else if (method === 'POST' && (path === '/api/weight' || path === '/api/weight/')) name = 'weigh_in_failed';
  else if (status >= 500) name = 'request_failed';
  if (!name) return;

  await track(prisma, userId, name, { reason, route, method, status });
}
