import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { requireAuth, type AuthedRequest } from '../auth/index.js';
import { getPrisma } from '../db/client.js';
import { createPushSender } from '../push/factory.js';
import { TEST_PUSHES, type TestPushKind } from '../push/testPushes.js';

const registerBody = z.object({
  token: z.string().min(1).max(400),
  kind: z.enum(['alert', 'live_activity_start']).default('alert'),
  environment: z.enum(['production', 'sandbox']).default('production'),
});

export async function pushTokenRoutes(app: FastifyInstance): Promise<void> {
  app.addHook('preHandler', requireAuth(app));

  // Register (or refresh) a device's APNs token.
  app.post('/', async (req) => {
    const { token, kind, environment } = registerBody.parse(req.body);
    const userId = (req as AuthedRequest).userId;

    await getPrisma().pushToken.upsert({
      where: { token },
      create: { userId, token, kind, environment, platform: 'ios' },
      update: { userId, kind, environment, lastSeenAt: new Date() },
    });
    return { ok: true };
  });

  // Unregister on sign-out.
  app.delete('/:token', async (req) => {
    const token = z.object({ token: z.string().min(1) }).parse(req.params).token;
    await getPrisma().pushToken.deleteMany({
      where: { token, userId: (req as AuthedRequest).userId },
    });
    return { ok: true };
  });

  // Admin or trainer only: a sample of one kind of check-in notification to this account's
  // own devices, and what the server knows about them. Creates no check-in.
  app.get('/test', async (req) => {
    await requireAdmin(req);
    const tokens = await tokensOf((req as AuthedRequest).userId);
    return { kinds: TEST_PUSHES.map(({ kind, label }) => ({ kind, label })), tokens };
  });

  app.post('/test', async (req) => {
    await requireAdmin(req);
    const { kind } = z.object({ kind: z.enum(TEST_PUSHES.map((t) => t.kind) as [TestPushKind, ...TestPushKind[]]) }).parse(req.body);
    const userId = (req as AuthedRequest).userId;
    const sample = TEST_PUSHES.find((t) => t.kind === kind)!;
    const tokens = await tokensOf(userId);
    const alerts = await getPrisma().pushToken.findMany({ where: { userId, kind: 'alert' }, select: { token: true } });
    if (alerts.length === 0) return { sent: 0, attempted: 0, error: 'no_push_token', tokens };

    const result = await createPushSender().send(alerts.map((t) => t.token), {
      userId,
      checkInId: `test-${kind}`,
      tier: sample.tier,
      title: 'SetPoint',
      body: `Test · ${sample.body}`,
      category: sample.category,
      plain: 'plain' in sample ? sample.plain : undefined,
    });
    if (result.invalidTokens.length > 0) {
      await getPrisma().pushToken.deleteMany({ where: { token: { in: result.invalidTokens } } });
    }
    return { sent: result.sent, attempted: result.attempted, failed: result.failed, error: result.error ?? null, removed: result.invalidTokens.length, tokens };
  });

  async function requireAdmin(req: unknown): Promise<void> {
    const user = await getPrisma().user.findUnique({ where: { id: (req as AuthedRequest).userId }, select: { role: true } });
    if (user?.role !== 'ADMIN' && user?.role !== 'TRAINER') throw app.httpErrors.forbidden('admin only');
  }

  async function tokensOf(userId: string) {
    const rows = await getPrisma().pushToken.findMany({
      where: { userId, kind: 'alert' },
      select: { environment: true, lastSeenAt: true },
      orderBy: { lastSeenAt: 'desc' },
    });
    return rows.map((r) => ({ environment: r.environment, lastSeenAt: r.lastSeenAt.toISOString() }));
  }
}
