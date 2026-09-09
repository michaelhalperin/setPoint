import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { requireAuth, type AuthedRequest } from '../auth/index.js';
import { getPrisma } from '../db/client.js';
import { ENGINE_CONFIG } from '../engine/index.js';

const params = z.object({ id: z.string().min(1) });

type CheckInWithPrescription = {
  id: string;
  tier: number;
  status: string;
  message: string | null;
  deferUntil: Date | null;
  feedbackPositive: boolean | null;
  createdAt: Date;
  prescription: {
    id: string;
    totalKcal: number;
    totalProteinG: number;
    items: { name: string; quantity: number; kcal: number; proteinG: number }[];
  } | null;
};

function serialize(ci: CheckInWithPrescription) {
  return {
    id: ci.id,
    tier: ci.tier,
    status: ci.status,
    message: ci.message,
    deferUntil: ci.deferUntil?.toISOString() ?? null,
    feedbackPositive: ci.feedbackPositive,
    createdAt: ci.createdAt.toISOString(),
    prescription: ci.prescription
      ? {
          id: ci.prescription.id,
          totalKcal: ci.prescription.totalKcal,
          totalProteinG: ci.prescription.totalProteinG,
          items: ci.prescription.items.map((i) => ({
            name: i.name,
            quantity: i.quantity,
            kcal: i.kcal,
            proteinG: i.proteinG,
          })),
        }
      : null,
  };
}

export async function checkInRoutes(app: FastifyInstance): Promise<void> {
  app.addHook('preHandler', requireAuth(app));

  // Fetch one check-in (e.g. the landing target of a notification deep-link).
  app.get('/:id', async (req) => {
    const { id } = params.parse(req.params);
    const ci = await getPrisma().checkIn.findFirst({
      where: { id, userId: (req as AuthedRequest).userId },
      include: { prescription: { include: { items: true } } },
    });
    if (!ci) throw app.httpErrors.notFound('check-in not found');
    return serialize(ci);
  });

  // Defer / snooze (§2). The scoring job re-checks when `deferUntil` passes.
  app.post('/:id/defer', async (req) => {
    const { id } = params.parse(req.params);
    const deferUntil = new Date(Date.now() + ENGINE_CONFIG.snoozeHours * 3_600_000);
    const result = await getPrisma().checkIn.updateMany({
      where: {
        id,
        userId: (req as AuthedRequest).userId,
        status: { in: ['PENDING', 'DEFERRED'] },
      },
      data: { status: 'DEFERRED', deferUntil, deferCount: { increment: 1 } },
    });
    if (result.count === 0) throw app.httpErrors.notFound('no active check-in with that id');
    return { deferred: true, deferUntil: deferUntil.toISOString() };
  });

  // "Was this right?" — labeled feedback for beta tuning (§8).
  app.post('/:id/feedback', async (req) => {
    const { id } = params.parse(req.params);
    const { positive } = z.object({ positive: z.boolean() }).parse(req.body);
    const result = await getPrisma().checkIn.updateMany({
      where: { id, userId: (req as AuthedRequest).userId },
      data: { feedbackPositive: positive, feedbackAt: new Date() },
    });
    if (result.count === 0) throw app.httpErrors.notFound('check-in not found');
    return { ok: true, feedbackPositive: positive };
  });
}
