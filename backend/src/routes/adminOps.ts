import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { gatherDelivery, gatherMachine, gatherNow, gatherPerson } from '../admin/ops.js';
import { getPrisma } from '../db/client.js';
import { createPushSender } from '../push/factory.js';
import { requireAdmin } from './admin.js';

const dayStart = z.object({
  /** The admin's local midnight, as ISO. Defaults to the last 24 hours. */
  since: z.string().datetime().optional(),
});

/** Read-only data for the ops dashboard (/ops), plus two person actions. */
export async function adminOpsRoutes(app: FastifyInstance): Promise<void> {
  app.addHook('preHandler', requireAdmin(app));

  const since = (q: unknown, now: Date) => {
    const { since } = dayStart.parse(q);
    return since ? new Date(since) : new Date(now.getTime() - 24 * 3_600_000);
  };

  app.get('/ops/now', async (req) => {
    const now = new Date();
    return gatherNow(getPrisma(), now, since(req.query, now));
  });

  app.get('/ops/person/:id', async (req) => {
    const { id } = z.object({ id: z.string().min(1) }).parse(req.params);
    const person = await gatherPerson(getPrisma(), id, new Date());
    if (!person) throw app.httpErrors.notFound('no such person');
    return person;
  });

  app.get('/ops/delivery', async (req) => {
    const q = z.object({ days: z.coerce.number().int().min(1).max(90).default(7), tzOffsetMin: z.coerce.number().int().min(-840).max(840).default(0) }).parse(req.query);
    return gatherDelivery(getPrisma(), new Date(), q.days, q.tzOffsetMin);
  });

  app.get('/ops/machine', async (req) => {
    const now = new Date();
    return gatherMachine(getPrisma(), now, since(req.query, now));
  });

  // A plain test notification to this person's own devices.
  app.post('/ops/person/:id/test-push', async (req) => {
    const { id } = z.object({ id: z.string().min(1) }).parse(req.params);
    const tokens = await getPrisma().pushToken.findMany({ where: { userId: id, kind: 'alert' }, select: { token: true } });
    if (tokens.length === 0) return { sent: 0, attempted: 0, error: 'no_push_token' };
    const result = await createPushSender().send(tokens.map((t) => t.token), {
      userId: id,
      checkInId: 'test-admin',
      tier: 1,
      title: 'SetPoint',
      body: 'Test from the admin. If you can read this, notifications work.',
      plain: true,
    });
    if (result.invalidTokens.length > 0) {
      await getPrisma().pushToken.deleteMany({ where: { token: { in: result.invalidTokens } } });
    }
    return { sent: result.sent, attempted: result.attempted, failed: result.failed, error: result.error ?? null };
  });

  // Clears a 24-hour back-off after repeated misses, and the miss counter.
  app.post('/ops/person/:id/reset-backoff', async (req) => {
    const { id } = z.object({ id: z.string().min(1) }).parse(req.params);
    const prisma = getPrisma();
    const user = await prisma.user.findUnique({ where: { id }, select: { id: true } });
    if (!user) throw app.httpErrors.notFound('no such person');
    await prisma.escalationState.upsert({
      where: { userId: id },
      create: { userId: id },
      update: { backedOffUntil: null, consecutiveMisses: 0, currentTier: 1 },
    });
    return { ok: true };
  });
}
