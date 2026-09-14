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
});
