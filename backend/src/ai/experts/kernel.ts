import { Prisma } from '@prisma/client';
import type { PrismaClient } from '@prisma/client';
import { getAnthropic } from '../client.js';
import { env } from '../../env.js';
import { flagOn } from '../../flags/index.js';
import { consumeAiQuota } from '../quota.js';
import { track } from '../../analytics/events.js';
import {
  EXPERT_KIND,
  PROPOSAL_TTL_MS,
  TODAY_CHIP_MIN_KCAL,
  type ExpertLang,
  type PlateArgs,
  type ProposalCard,
  type TranscriptTurn,
} from './kinds.js';
import { chips, copy } from './staticCopy.js';
import { detectDistress } from './distress.js';
import { lockActive, recordTrip } from './lock.js';
import { assembleSnapshot } from './snapshot.js';
import { suggestPlate } from './suggestPlate.js';
import { runModelTurn } from './conversant.js';
import { validateOutput } from './validator.js';
import { logMeal } from '../../meals/logMeal.js';
import { createMealParser } from '../parseMeal.js';

export type ExpertState =
  | 'off'
  | 'paused'
  | 'ineligible'
  | 'locked'
  | 'needs_consent'
  | 'ready';

function readTranscript(raw: unknown): TranscriptTurn[] {
  if (!Array.isArray(raw)) return [];
  return raw.filter(
    (t): t is TranscriptTurn =>
      !!t &&
      (t.role === 'user' || t.role === 'assistant') &&
      typeof t.content === 'string' &&
      typeof t.at === 'string',
  );
}

function cardFromArgs(id: string, args: PlateArgs, expiresAt: Date, lang: ExpertLang): ProposalCard {
  return {
    id,
    kind: 'suggest_plate',
    title: copy(lang).confirmTitle,
    summary: args.summary,
    localDate: args.localDate,
    timezone: args.timezone,
    expiresAt: expiresAt.toISOString(),
    items: args.items,
    totals: args.totals,
  };
}

export async function nutritionEnabled(prisma: PrismaClient, userId: string): Promise<boolean> {
  if (env.EXPERT_NUTRITION_ENABLED !== 'true') return false;
  const [user, row] = await Promise.all([
    prisma.user.findUnique({ where: { id: userId }, select: { id: true, role: true, group: true } }),
    prisma.featureFlag.findUnique({ where: { key: 'nutrition_chat' } }),
  ]);
  if (!user) return false;
  return flagOn('nutrition_chat', user, row ?? undefined);
}

export function isLayer1Reason(reason: string | null | undefined): boolean {
  return reason === 'EATING_DISORDER_SCREEN' || reason === 'MEDICAL_SUPERVISION';
}

async function eligibilityReason(prisma: PrismaClient, userId: string) {
  const safety = await prisma.safetyScreening.findUnique({
    where: { userId },
    select: { enforcementDisabledReason: true },
  });
  return safety?.enforcementDisabledReason ?? null;
}

export async function getNutritionThread(
  prisma: PrismaClient,
  userId: string,
  lang: ExpertLang,
) {
  const c = copy(lang);
  if (env.EXPERT_NUTRITION_ENABLED !== 'true') {
    return { state: 'paused' as const, message: c.paused, remainingKcal: 0, chips: [], consent: null, messages: [], pendingProposal: null };
  }
  const on = await nutritionEnabled(prisma, userId);
  if (!on) {
    return { state: 'off' as const, message: c.paused, remainingKcal: 0, chips: [], consent: null, messages: [], pendingProposal: null };
  }

  const reason = await eligibilityReason(prisma, userId);
  if (isLayer1Reason(reason)) {
    return {
      state: 'ineligible' as const,
      message: c.ineligible,
      remainingKcal: 0,
      chips: [],
      consent: null,
      messages: [],
      pendingProposal: null,
    };
  }

  const convo = await prisma.expertConversation.upsert({
    where: { userId_kind: { userId, kind: EXPERT_KIND } },
    create: { userId, kind: EXPERT_KIND },
    update: {},
    include: { proposals: { where: { status: 'PENDING' }, orderBy: { createdAt: 'desc' }, take: 1 } },
  });

  const snapshot = await assembleSnapshot(prisma, userId, lang);
  const remainingKcal = snapshot?.remainingKcal ?? 0;

  if (lockActive(convo.lockedUntil)) {
    return {
      state: 'locked' as const,
      message: c.locked,
      remainingKcal,
      chips: [],
      consent: null,
      messages: readTranscript(convo.transcript),
      pendingProposal: null,
    };
  }

  if (!convo.consentedAt) {
    return {
      state: 'needs_consent' as const,
      message: c.consentBody,
      remainingKcal,
      chips: [],
      consent: { title: c.consentTitle, body: c.consentBody, review: c.consentReview, accept: c.consentAccept, decline: c.consentDecline },
      messages: [],
      pendingProposal: null,
    };
  }

  let messages = readTranscript(convo.transcript);
  if (messages.length === 0) {
    messages = [{ role: 'assistant', content: c.opener, at: new Date().toISOString() }];
    await prisma.expertConversation.update({ where: { id: convo.id }, data: { transcript: messages } });
  }

  const pending = convo.proposals[0];
  await track(prisma, userId, 'expert_open', { kind: 'nutrition' }, { dedupeKey: `expert_open:${userId}:${snapshot?.localDate ?? 'x'}` });

  return {
    state: 'ready' as const,
    message: null,
    remainingKcal,
    chipMinKcal: TODAY_CHIP_MIN_KCAL,
    chips: chips(lang),
    consent: null,
    messages,
    pendingProposal: pending ? cardFromArgs(pending.id, pending.args as PlateArgs, pending.expiresAt, lang) : null,
    reviewConsent: !!convo.reviewConsentAt,
    stages: { look: c.stageLook, plate: c.stagePlate, check: c.stageCheck },
  };
}

export async function consentNutrition(
  prisma: PrismaClient,
  userId: string,
  input: { accept: boolean; reviewConsent: boolean; lang: ExpertLang },
) {
  if (env.EXPERT_NUTRITION_ENABLED !== 'true' || !(await nutritionEnabled(prisma, userId))) {
    return getNutritionThread(prisma, userId, input.lang);
  }
  const reason = await eligibilityReason(prisma, userId);
  if (isLayer1Reason(reason)) return getNutritionThread(prisma, userId, input.lang);

  if (!input.accept) return getNutritionThread(prisma, userId, input.lang);

  const now = new Date();
  await prisma.expertConversation.upsert({
    where: { userId_kind: { userId, kind: EXPERT_KIND } },
    create: {
      userId,
      kind: EXPERT_KIND,
      consentedAt: now,
      reviewConsentAt: input.reviewConsent ? now : null,
    },
    update: {
      consentedAt: now,
      reviewConsentAt: input.reviewConsent ? now : null,
    },
  });
  await track(prisma, userId, 'expert_consent', { kind: 'nutrition', review: input.reviewConsent ? 1 : 0 });
  return getNutritionThread(prisma, userId, input.lang);
}

export async function sendNutritionTurn(
  prisma: PrismaClient,
  userId: string,
  input: { message: string; lang: ExpertLang },
) {
  const lang = input.lang;
  const c = copy(lang);
  const thread = await getNutritionThread(prisma, userId, lang);
  if (thread.state !== 'ready') return thread;

  const convo = await prisma.expertConversation.findUnique({
    where: { userId_kind: { userId, kind: EXPERT_KIND } },
  });
  if (!convo) return thread;

  const snapshot = await assembleSnapshot(prisma, userId, lang);
  if (!snapshot) return thread;

  await consumeAiQuota(prisma, userId, 'nutrition_message');
  await track(prisma, userId, 'expert_send', { kind: 'nutrition' });

  const history = readTranscript(convo.transcript);
  const userTurn: TranscriptTurn = { role: 'user', content: input.message.slice(0, 1000), at: new Date().toISOString() };
  history.push(userTurn);

  const distress = detectDistress(input.message);
  if (distress) {
    const { lockedUntil } = await recordTrip(prisma, {
      userId,
      conversationId: convo.id,
      layer: 'input',
      code: distress.code,
      userMessage: input.message,
    });
    history.push({ role: 'assistant', content: lockedUntil ? c.locked : c.distress, at: new Date().toISOString() });
    await prisma.expertConversation.update({ where: { id: convo.id }, data: { transcript: history } });
    await track(prisma, userId, 'expert_safety_trip', { kind: 'nutrition', layer: 'input' });
    if (lockedUntil) await track(prisma, userId, 'expert_safety_lock', { kind: 'nutrition' });
    return getNutritionThread(prisma, userId, lang);
  }

  const client = getAnthropic();
  const turn = await runModelTurn(client, history, snapshot, lang);

  if (turn.distressFlag) {
    const { lockedUntil } = await recordTrip(prisma, {
      userId,
      conversationId: convo.id,
      layer: 'model_flag',
      code: 'distress_flag',
      userMessage: input.message,
      discardedReply: turn.reply,
    });
    history.push({ role: 'assistant', content: lockedUntil ? c.locked : c.distress, at: new Date().toISOString() });
    await prisma.expertConversation.update({ where: { id: convo.id }, data: { transcript: history } });
    await track(prisma, userId, 'expert_safety_trip', { kind: 'nutrition', layer: 'model_flag' });
    return getNutritionThread(prisma, userId, lang);
  }

  let plate: PlateArgs | null = null;
  if (turn.shape) {
    plate = await suggestPlate(prisma, userId, snapshot, turn.shape);
  }

  const assistantText = turn.reply;
  const toolArgs = plate ?? turn.shape;
  const validated = await validateOutput(client, {
    lang,
    lastUserMessage: input.message,
    assistantText,
    toolArgs,
    allergenTokens: snapshot.restrictions,
    remainingKcal: snapshot.remainingKcal,
    goal: snapshot.goal,
  });

  if (!validated.ok) {
    await recordTrip(prisma, {
      userId,
      conversationId: convo.id,
      layer: validated.codes.some((x) => x.startsWith('validator')) ? 'output_haiku' : 'output_rules',
      code: validated.codes[0] ?? 'output',
      userMessage: input.message,
      discardedReply: assistantText,
    });
    await track(prisma, userId, 'expert_safety_trip', { kind: 'nutrition', layer: 'output' });
    history.push({ role: 'assistant', content: c.validatorFail, at: new Date().toISOString() });
    await prisma.expertConversation.update({ where: { id: convo.id }, data: { transcript: history } });
    return getNutritionThread(prisma, userId, lang);
  }

  history.push({ role: 'assistant', content: assistantText, at: new Date().toISOString() });

  if (turn.shape && !plate) {
    history.push({ role: 'assistant', content: c.emptyPlate, at: new Date().toISOString() });
    await prisma.expertConversation.update({ where: { id: convo.id }, data: { transcript: history } });
    return getNutritionThread(prisma, userId, lang);
  }

  await prisma.$transaction(async (tx) => {
    await tx.expertProposal.updateMany({
      where: { conversationId: convo.id, status: 'PENDING' },
      data: { status: 'SUPERSEDED', resolvedAt: new Date() },
    });
    if (plate) {
      const expiresAt = new Date(
        Math.min(
          new Date(`${snapshot.localDate}T23:59:59`).getTime(),
          Date.now() + PROPOSAL_TTL_MS,
        ),
      );
      await tx.expertProposal.create({
        data: {
          conversationId: convo.id,
          kind: 'suggest_plate',
          args: plate as unknown as Prisma.InputJsonValue,
          expiresAt,
        },
      });
    }
    await tx.expertConversation.update({ where: { id: convo.id }, data: { transcript: history } });
  });

  return getNutritionThread(prisma, userId, lang);
}

export async function confirmNutritionProposal(
  prisma: PrismaClient,
  userId: string,
  proposalId: string,
  lang: ExpertLang,
) {
  const c = copy(lang);
  if (!(await nutritionEnabled(prisma, userId))) {
    return { ok: false as const, error: c.paused };
  }

  const proposal = await prisma.expertProposal.findFirst({
    where: { id: proposalId, conversation: { userId, kind: EXPERT_KIND } },
    include: { conversation: true },
  });
  if (!proposal) return { ok: false as const, error: c.malformed };
  if (proposal.status === 'CONFIRMED') {
    return { ok: true as const, already: true };
  }
  if (proposal.status !== 'PENDING') return { ok: false as const, error: c.malformed };
  if (proposal.expiresAt.getTime() < Date.now()) {
    await prisma.expertProposal.update({
      where: { id: proposal.id },
      data: { status: 'EXPIRED', resolvedAt: new Date() },
    });
    return { ok: false as const, error: c.emptyPlate };
  }

  const reason = await eligibilityReason(prisma, userId);
  if (isLayer1Reason(reason)) return { ok: false as const, error: c.ineligible };
  if (lockActive(proposal.conversation.lockedUntil)) return { ok: false as const, error: c.locked };

  const args = proposal.args as PlateArgs;
  const snapshot = await assembleSnapshot(prisma, userId, lang);
  if (!snapshot || snapshot.localDate !== args.localDate) {
    await prisma.expertProposal.update({
      where: { id: proposal.id },
      data: { status: 'INVALID', resolvedAt: new Date() },
    });
    return { ok: false as const, error: c.emptyPlate };
  }

  const client = getAnthropic();
  await logMeal(
    {
      prisma,
      parseMeal: client ? createMealParser(client) : null,
    },
    userId,
    {
      clientId: proposal.id,
      text: args.summary,
      macros: args.totals,
    },
  );

  await prisma.expertProposal.update({
    where: { id: proposal.id },
    data: { status: 'CONFIRMED', resolvedAt: new Date() },
  });
  await track(prisma, userId, 'expert_confirm', { kind: 'nutrition', proposalKind: 'suggest_plate' });
  return { ok: true as const, already: false };
}

export async function dismissNutritionProposal(
  prisma: PrismaClient,
  userId: string,
  proposalId: string,
) {
  const proposal = await prisma.expertProposal.findFirst({
    where: { id: proposalId, conversation: { userId, kind: EXPERT_KIND }, status: 'PENDING' },
  });
  if (!proposal) return;
  await prisma.expertProposal.update({
    where: { id: proposal.id },
    data: { status: 'DISMISSED', resolvedAt: new Date() },
  });
  await track(prisma, userId, 'expert_dismiss', { kind: 'nutrition', proposalKind: 'suggest_plate' });
}

export async function clearNutritionThread(prisma: PrismaClient, userId: string) {
  const convo = await prisma.expertConversation.findUnique({
    where: { userId_kind: { userId, kind: EXPERT_KIND } },
  });
  if (!convo) return;
  await prisma.$transaction([
    prisma.expertProposal.updateMany({
      where: { conversationId: convo.id, status: 'PENDING' },
      data: { status: 'DISMISSED', resolvedAt: new Date() },
    }),
    prisma.expertConversation.update({
      where: { id: convo.id },
      data: { transcript: [] },
    }),
  ]);
}
