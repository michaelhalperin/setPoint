import type { FastifyInstance } from 'fastify';
import { OPS_PAGE_HTML } from '../admin/opsPage.js';

/**
 * The owner's ops dashboard. The page itself is public and holds no data — every
 * number comes from /api/admin after signing in with the admin secret.
 */
export async function adminPageRoutes(app: FastifyInstance): Promise<void> {
  const send = (html: string) => async (_req: unknown, reply: import('fastify').FastifyReply) => {
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
          "img-src 'self' data: https:",
          "frame-ancestors 'none'",
          "base-uri 'none'",
          "form-action 'none'",
        ].join('; '),
      );
    return html;
  };
  app.get('/admin', send(OPS_PAGE_HTML));
  // The dashboard's first address.
  app.get('/ops', async (_req, reply) => reply.redirect('/admin', 302));
}
