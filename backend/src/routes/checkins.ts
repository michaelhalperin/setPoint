import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { getAnthropic } from '../ai/client.js';
import {
  createAiTierThree,
  fallbackTierThree,
  type ConversationTurn,
} from '../ai/tierThree.js';
import { consumeAiQuota } from '../ai/quota.js';
import { requireAuth, type AuthedRequest } from '../auth/index.js';
import { getPrisma } from '../db/client.js';
import { ENGINE_CONFIG, type Goal } from '../engine/index.js';

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

const turnSchema = z.array(
  z.object({ role: z.enum(['user', 'assistant']), content: z.string(), at: z.string().optional() }),
);

function readTranscript(raw: unknown): (ConversationTurn & { at?: string })[] {
  const parsed = turnSchema.safeParse(raw);
  return parsed.success ? parsed.data : [];
}

function conversant() {
  const client = getAnthropic();
  return client ? createAiTierThree(client) : fallbackTierThree;
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
  // An optional `minutes` lets the user pick the snooze length (e.g. "in 1 hour"
  // or "after my next meal", the app computing the gap); it's clamped to a sane
  // band and falls back to the engine default.
  app.post('/:id/defer', async (req) => {
    const { id } = params.parse(req.params);
    const { minutes } = z
      .object({ minutes: z.number().int().min(15).max(360).optional() })
      .parse(req.body ?? {});
    const snoozeMs = (minutes ?? ENGINE_CONFIG.snoozeHours * 60) * 60_000;
    const deferUntil = new Date(Date.now() + snoozeMs);
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

  // Tier-3 "this isn't working right now" conversation (§2).
  app.get('/:id/conversation', async (req) => {
    const { id } = params.parse(req.params);
    const userId = (req as AuthedRequest).userId;
    const prisma = getPrisma();

    let convo = await prisma.escalationConversation.findFirst({ where: { checkInId: id, userId } });
    if (!convo) throw app.httpErrors.notFound('no conversation for that check-in');

    let messages = readTranscript(convo.transcript);
    if (messages.length === 0) {
      const opener = conversant().opener({ goal: 'BULK', recentMisses: ENGINE_CONFIG.missesBeforeTier3 });
      messages = [{ role: 'assistant', content: opener, at: new Date().toISOString() }];
      convo = await prisma.escalationConversation.update({
        where: { id: convo.id },
        data: { transcript: messages },
      });
    }

    return { messages, outcome: convo.outcome, resolved: convo.resolvedAt !== null };
  });

  app.post('/:id/conversation', async (req) => {
    const { id } = params.parse(req.params);
    const { message } = z.object({ message: z.string().min(1).max(1000) }).parse(req.body);
    const userId = (req as AuthedRequest).userId;
    const prisma = getPrisma();

    const [convo, profile] = await Promise.all([
      prisma.escalationConversation.findFirst({ where: { checkInId: id, userId } }),
      prisma.onboardingProfile.findUnique({ where: { userId }, select: { goal: true } }),
    ]);
    if (!convo) throw app.httpErrors.notFound('no conversation for that check-in');
    if (convo.resolvedAt) throw app.httpErrors.conflict('this conversation is closed');

    // Each turn calls the model — count it against the user's AI quota.
    await consumeAiQuota(prisma, userId, 'tier3_message');

    const now = new Date();
    const history: (ConversationTurn & { at?: string })[] = readTranscript(convo.transcript);
    history.push({ role: 'user', content: message, at: now.toISOString() });

    const result = await conversant().respond(
      history.map((t) => ({ role: t.role, content: t.content })),
      { goal: (profile?.goal as Goal) ?? 'BULK', recentMisses: ENGINE_CONFIG.missesBeforeTier3 },
    );
    history.push({ role: 'assistant', content: result.reply, at: new Date().toISOString() });

    const closing = result.done || result.outcome !== 'NONE';

    await prisma.$transaction(async (tx) => {
      await tx.escalationConversation.update({
        where: { id: convo.id },
        data: {
          transcript: history,
          outcome: closing ? result.outcome : convo.outcome,
          resolvedAt: closing ? now : null,
        },
      });

      if (closing) {
        await tx.checkIn.updateMany({
          where: { id, userId, status: 'PENDING' },
          data: { status: 'ESCALATED', resolvedAt: now },
        });
        if (result.outcome === 'PAUSE_CHECKINS') {
          await tx.escalationState.upsert({
            where: { userId },
            create: { userId, checkInsPaused: true },
            update: { checkInsPaused: true },
          });
        }
      }
    });

    return {
      messages: history,
      outcome: closing ? result.outcome : convo.outcome,
      resolved: closing,
    };
  });
}
