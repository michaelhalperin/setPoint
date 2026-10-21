import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { requireAuth, type AuthedRequest } from '../auth/index.js';
import { getPrisma } from '../db/client.js';
import {
  clearNutritionThread,
  confirmNutritionProposal,
  consentNutrition,
  dismissNutritionProposal,
  getNutritionThread,
  sendNutritionTurn,
} from '../ai/experts/kernel.js';

const langSchema = z.enum(['en', 'he']).default('en');

export async function expertRoutes(app: FastifyInstance): Promise<void> {
  app.addHook('preHandler', requireAuth(app));

  app.get('/nutrition', async (req) => {
    const q = z.object({ lang: langSchema }).parse(req.query);
    return getNutritionThread(getPrisma(), (req as AuthedRequest).userId, q.lang);
  });

  app.post('/nutrition/consent', async (req) => {
    const body = z
      .object({
        accept: z.boolean(),
        reviewConsent: z.boolean().default(false),
        lang: langSchema,
      })
      .parse(req.body);
    return consentNutrition(getPrisma(), (req as AuthedRequest).userId, body);
  });

  app.post('/nutrition', async (req) => {
    const body = z
      .object({
        message: z.string().min(1).max(1000),
        lang: langSchema,
      })
      .parse(req.body);
    return sendNutritionTurn(getPrisma(), (req as AuthedRequest).userId, body);
  });

  app.post('/nutrition/confirm', async (req) => {
    const body = z.object({ proposalId: z.string().min(1), lang: langSchema }).parse(req.body);
    const result = await confirmNutritionProposal(
      getPrisma(),
      (req as AuthedRequest).userId,
      body.proposalId,
      body.lang,
    );
    if (!result.ok) throw app.httpErrors.conflict(result.error);
    return result;
  });

  app.post('/nutrition/dismiss', async (req) => {
    const body = z.object({ proposalId: z.string().min(1) }).parse(req.body);
    await dismissNutritionProposal(getPrisma(), (req as AuthedRequest).userId, body.proposalId);
    return { ok: true };
  });

  app.post('/nutrition/clear', async (req) => {
    await clearNutritionThread(getPrisma(), (req as AuthedRequest).userId);
    return { ok: true };
  });
}
