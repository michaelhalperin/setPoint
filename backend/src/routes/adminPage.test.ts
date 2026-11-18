import Fastify from 'fastify';
import { describe, expect, it } from 'vitest';
import { adminPageRoutes } from './adminPage.js';

describe('GET /admin', () => {
  it('serves the admin console, locked down and never cached', async () => {
    const app = Fastify();
    await app.register(adminPageRoutes);
    const res = await app.inject({ url: '/admin' });
    expect(res.statusCode).toBe(200);
    expect(res.headers['cache-control']).toBe('no-store');
    expect(res.headers['x-frame-options']).toBe('DENY');
    expect(res.body).toContain('<title>SetPoint admin</title>');
    for (const path of ['/control', '/run/', '/broadcast', '/health-feed', '/catalog', '/audit', '/subscriptions']) {
      expect(res.body).toContain(path);
    }
    expect(res.body).not.toMatch(/@[a-z0-9-]+\.[a-z]{2,}/i);
  });

  it('serves the classic ops dashboard, locked down and never cached', async () => {
    const app = Fastify();
    await app.register(adminPageRoutes);
    const res = await app.inject({ url: '/admin/classic' });
    expect(res.statusCode).toBe(200);
    expect(res.headers['content-type']).toContain('text/html');
    expect(res.headers['cache-control']).toBe('no-store');
    expect(res.headers['x-frame-options']).toBe('DENY');
    expect(res.headers['content-security-policy']).toContain("connect-src 'self'");
    expect(res.body).toContain('<title>SetPoint ops</title>');
    expect(res.body).toContain("['access', 'Access']");
    expect(res.body).toContain('/api/admin/invites');
    expect(res.body).toContain('/api/admin/flags');
    // The page holds no data of its own.
    expect(res.body).not.toMatch(/@[a-z0-9-]+\.[a-z]{2,}/i);
  });

  it('sends the old /ops address to /admin', async () => {
    const app = Fastify();
    await app.register(adminPageRoutes);
    const res = await app.inject({ url: '/ops' });
    expect(res.statusCode).toBe(302);
    expect(res.headers.location).toBe('/admin');
  });
});
