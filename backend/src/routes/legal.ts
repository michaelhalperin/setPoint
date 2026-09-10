import type { FastifyInstance } from 'fastify';
import { env } from '../env.js';
import {
  LEGAL_EFFECTIVE_DATE,
  LEGAL_VERSION,
  privacyPolicyHtml,
  termsOfServiceHtml,
} from '../legal/content.js';

/**
 * Public legal pages (plan §4). Served at clean top-level URLs so the App Store
 * listing and the app's Settings → Legal links can point straight at them.
 */
export async function legalRoutes(app: FastifyInstance): Promise<void> {
  app.get('/privacy', async (_req, reply) => {
    reply.type('text/html; charset=utf-8');
    return privacyPolicyHtml();
  });

  app.get('/terms', async (_req, reply) => {
    reply.type('text/html; charset=utf-8');
    return termsOfServiceHtml();
  });

  // Machine-readable pointer for the app: which version is current + where to link.
  app.get('/api/legal', async () => ({
    version: LEGAL_VERSION,
    effectiveDate: LEGAL_EFFECTIVE_DATE,
    privacyUrl: '/privacy',
    termsUrl: '/terms',
    supportEmail: env.SUPPORT_EMAIL,
  }));
}
