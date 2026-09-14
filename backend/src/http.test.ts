import { afterAll, describe, expect, it } from 'vitest';
import { buildApp } from './app.js';

const app = await buildApp();

afterAll(async () => {
  await app.close();
});

describe('HTTP contracts', () => {
  it('serves a health payload without requiring a database', async () => {
    const res = await app.inject({ method: 'GET', url: '/api/health' });
    expect(res.statusCode).toBe(200);
    const body = res.json();
    expect(body.status).toMatch(/ok|degraded/);
    expect(['up', 'down']).toContain(body.db);
  });

  it('serves privacy and terms pages', async () => {
    const privacy = await app.inject({ method: 'GET', url: '/privacy' });
    expect(privacy.statusCode).toBe(200);
    expect(privacy.body).toContain('observed meal behavior');

    const terms = await app.inject({ method: 'GET', url: '/terms' });
    expect(terms.statusCode).toBe(200);
    expect(terms.body).toContain('not a medical device');
  });

  it('rejects oversized JSON bodies', async () => {
    const res = await app.inject({
      method: 'POST',
      url: '/api/auth/dev',
      headers: { 'content-type': 'application/json' },
      payload: 'x'.repeat(1_200_000),
    });
    expect(res.statusCode).toBeGreaterThanOrEqual(400);
  });

  it('rejects unauthenticated meal logs', async () => {
    const res = await app.inject({
      method: 'POST',
      url: '/api/meals',
      payload: { text: 'oats' },
    });
    expect(res.statusCode).toBe(401);
  });

  it('rejects unauthenticated saved-meal and barcode lookups', async () => {
    const saved = await app.inject({ method: 'GET', url: '/api/saved-meals' });
    expect(saved.statusCode).toBe(401);
    const barcode = await app.inject({ method: 'GET', url: '/api/foods/barcode/3017620422003' });
    expect(barcode.statusCode).toBe(401);
  });

  it('rejects unauthenticated start-talk', async () => {
    const res = await app.inject({ method: 'POST', url: '/api/checkins/start-talk' });
    expect(res.statusCode).toBe(401);
  });

  it('rejects unauthenticated burn insights', async () => {
    const res = await app.inject({ method: 'GET', url: '/api/insights/burn' });
    expect(res.statusCode).toBe(401);
  });
});

describe('auth rate limiting', () => {
  it('answers 429 with retry-after once the shared limiter says no, and leaves other routes alone', async () => {
    const seen: string[] = [];
    const limited = await buildApp({
      authRateLimiter: async (key) => {
        seen.push(key);
        return { allowed: false, retryAfterSeconds: 42 };
      },
    });
    try {
      const res = await limited.inject({ method: 'POST', url: '/api/auth/dev', payload: {} });
      expect(res.statusCode).toBe(429);
      expect(res.headers['retry-after']).toBe('42');
      expect(seen[0]).toMatch(/^auth:/);

      const health = await limited.inject({ method: 'GET', url: '/api/health' });
      expect(health.statusCode).toBe(200);
      expect(seen).toHaveLength(1);
    } finally {
      await limited.close();
    }
  });

  it('lets sign-in through when the limiter itself is down', async () => {
    const broken = await buildApp({
      authRateLimiter: async () => {
        throw new Error('db down');
      },
    });
    try {
      const res = await broken.inject({ method: 'POST', url: '/api/auth/apple', payload: {} });
      expect(res.statusCode).not.toBe(429);
    } finally {
      await broken.close();
    }
  });
});
