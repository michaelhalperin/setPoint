import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { CLIENT_EVENTS, track } from '../analytics/events.js';
import { requireAuth, type AuthedRequest } from '../auth/index.js';
import { getPrisma } from '../db/client.js';

const body = z.object({
  name: z.enum(CLIENT_EVENTS),
  props: z.record(z.unknown()).optional(),
});

/** The few events only the app can see (opened, crashed, a log that never reached us). */
export async function eventRoutes(app: FastifyInstance): Promise<void> {
  // Open to accounts waiting for an invite, so the invite screen counts too.
  app.addHook('preHandler', requireAuth(app, { allowPendingInvite: true }));

  app.post('/', async (req) => {
    const { name, props } = body.parse(req.body);
    await track(getPrisma(), (req as AuthedRequest).userId, name, props as Record<string, string | number | boolean> | undefined);
    return { ok: true };
  });
}
