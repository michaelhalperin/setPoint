import Fastify from 'fastify';
import { describe, expect, it } from 'vitest';
import { adminPageRoutes } from '../routes/adminPage.js';

describe('GET /ops', () => {
  it('serves the ops dashboard, locked down, never cached, with no data inside', async () => {
    const app = Fastify();
    await app.register(adminPageRoutes);
    const res = await app.inject({ url: '/ops' });
    expect(res.statusCode).toBe(200);
    expect(res.headers['content-type']).toContain('text/html');
    expect(res.headers['cache-control']).toBe('no-store');
    expect(res.headers['x-frame-options']).toBe('DENY');
    expect(res.headers['content-security-policy']).toContain("connect-src 'self'");
    expect(res.body).toContain('<title>SetPoint ops</title>');
    expect(res.body).toContain('/api/admin/ops/now');
    expect(res.body).not.toMatch(/@[a-z0-9-]+\.[a-z]{2,}/i);
  });

  it('keeps the current dashboard at /admin', async () => {
    const app = Fastify();
    await app.register(adminPageRoutes);
    const res = await app.inject({ url: '/admin' });
    expect(res.body).toContain('<title>SetPoint Admin</title>');
  });
});

describe('the page script', () => {
  it('parses as JavaScript', async () => {
    const { OPS_PAGE_HTML } = await import('./opsPage.js');
    const script = OPS_PAGE_HTML.split('<script>')[1]!.split('</script>')[0]!;
    expect(() => new Function(script)).not.toThrow();
  });
});
