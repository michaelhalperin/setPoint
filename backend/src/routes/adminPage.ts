import type { FastifyInstance } from 'fastify';
import { ADMIN_DASHBOARD_HTML } from '../admin/dashboardPage.js';

/**
 * The owner's dashboard. The page itself is public and holds no data — every
 * number comes from /api/admin after signing in with the admin secret.
 */
export async function adminPageRoutes(app: FastifyInstance): Promise<void> {
  app.get('/admin', async (_req, reply) => {
    reply
      .type('text/html; charset=utf-8')
      .header('cache-control', 'no-store')
      .header('x-frame-options', 'DENY')
      .header('referrer-policy', 'no-referrer')
      .header('x-content-type-options', 'nosniff')
      .header(
        'content-security-policy',
        [
          "default-src 'none'",
          "script-src 'unsafe-inline'",
          "style-src 'unsafe-inline' https://fonts.googleapis.com",
          'font-src https://fonts.gstatic.com',
          "connect-src 'self'",
          "img-src 'self' data:",
          "frame-ancestors 'none'",
          "base-uri 'none'",
          "form-action 'none'",
        ].join('; '),
      );
    return ADMIN_DASHBOARD_HTML;
  });
}
