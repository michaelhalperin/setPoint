import Fastify from 'fastify';
import { describe, expect, it } from 'vitest';
import { adminPageRoutes } from './adminPage.js';

describe('GET /admin', () => {
  it('serves the dashboard page, locked down and never cached', async () => {
    const app = Fastify();
    await app.register(adminPageRoutes);
    const res = await app.inject({ url: '/admin' });
    expect(res.statusCode).toBe(200);
    expect(res.headers['content-type']).toContain('text/html');
    expect(res.headers['cache-control']).toBe('no-store');
    expect(res.headers['x-frame-options']).toBe('DENY');
    expect(res.headers['content-security-policy']).toContain("connect-src 'self'");
    expect(res.body).toContain('<title>SetPoint Admin</title>');
    expect(res.body).toContain("['notifications', 'Notifications']");
    expect(res.body).toContain("h('h2', { text: 'Problems' })");
    expect(res.body).toContain("h('h2', { text: 'Meals by source' })");
    expect(res.body).toContain("text: 'Delete listed'");
    expect(res.body).toContain("method: 'DELETE'");
    // The page holds no data of its own.
    expect(res.body).not.toMatch(/@[a-z0-9-]+\.[a-z]{2,}/i);
  });
});
