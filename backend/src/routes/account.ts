import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { AccountNotFoundError, deleteAccount } from '../account/deleteAccount.js';
import { requireAuth, type AuthedRequest } from '../auth/index.js';
import { OnboardingIncompleteError } from '../dashboard/home.js';
import { getPrisma } from '../db/client.js';
import { AlreadyOnboardedError, MissingTargetError, runOnboarding } from '../onboarding/onboard.js';
import { getSettings, updateSettings } from '../onboarding/settings.js';

const minutes = z.number().int().min(0).max(1439);
const mealTimes = z.object({ breakfastMin: minutes, lunchMin: minutes, dinnerMin: minutes });
const quietHours = z.object({ startMin: minutes, endMin: minutes });
const scoff = z.object({
  makeSelfSick: z.boolean(),
  lostControl: z.boolean(),
  lostOneStone: z.boolean(),
  believesFat: z.boolean(),
  foodDominates: z.boolean(),
});
const restriction = z.object({ label: z.string().min(1).max(80), source: z.string().optional() });

const onboardingBody = z.object({
  goal: z.enum(['BULK', 'DIET', 'MAINTAIN']),
  mode: z.enum(['BASIC', 'SMART']),
  timezone: z.string().optional(),
  sex: z.enum(['MALE', 'FEMALE', 'UNSPECIFIED']).optional(),
  birthDate: z.string().date().optional(),
  heightCm: z.number().positive().max(260).optional(),
  weightKg: z.number().positive().max(400).optional(),
  activityLevel: z.enum(['SEDENTARY', 'LIGHT', 'MODERATE', 'ACTIVE', 'VERY_ACTIVE']).optional(),
  targetWeightKg: z.number().positive().max(400).optional(),
  paceKgPerWeek: z.number().positive().max(2).optional(),
  dailyKcalTarget: z.number().int().min(800).max(8000).optional(),
  dailyProteinTargetG: z.number().int().min(0).max(400).optional(),
  mealTimes: mealTimes.optional(),
  quietHours: quietHours.optional(),
  safety: z.object({
    medicalSupervisionRequired: z.boolean(),
    scoff,
    restrictions: z.array(restriction).max(50).optional(),
    restrictionsFreeText: z.string().max(1000).optional(),
  }),
});

const settingsPatch = z
  .object({
    goal: z.enum(['BULK', 'DIET', 'MAINTAIN']).optional(),
    targetWeightKg: z.number().positive().max(400).nullable().optional(),
    paceKgPerWeek: z.number().positive().max(2).optional(),
    dailyKcalTarget: z.number().int().min(800).max(8000).optional(),
    dailyProteinTargetG: z.number().int().min(0).max(400).nullable().optional(),
    mealTimes: mealTimes.optional(),
    quietHours: quietHours.optional(),
    checkInsPaused: z.boolean().optional(),
    timezone: z.string().optional(),
    restrictions: z.array(restriction).max(50).optional(),
  })
  .refine((p) => Object.keys(p).length > 0, { message: 'no changes provided' });

const deleteBody = z.object({ confirmation: z.literal('delete my account') });

export async function accountRoutes(app: FastifyInstance): Promise<void> {
  app.addHook('preHandler', requireAuth(app));

  // Onboarding + safety screening + meal-time preferences (§3, §5.1).
  app.post('/onboarding', async (req) => {
    const input = onboardingBody.parse(req.body);
    try {
      return await runOnboarding({ prisma: getPrisma() }, (req as AuthedRequest).userId, input);
    } catch (err) {
      if (err instanceof AlreadyOnboardedError) throw app.httpErrors.conflict(err.message);
      if (err instanceof MissingTargetError) throw app.httpErrors.badRequest(err.message);
      throw err;
    }
  });

  app.get('/settings', async (req) => {
    try {
      return await getSettings({ prisma: getPrisma() }, (req as AuthedRequest).userId);
    } catch (err) {
      if (err instanceof OnboardingIncompleteError) throw app.httpErrors.conflict(err.message);
      throw err;
    }
  });

  app.patch('/settings', async (req) => {
    const patch = settingsPatch.parse(req.body);
    try {
      return await updateSettings({ prisma: getPrisma() }, (req as AuthedRequest).userId, patch);
    } catch (err) {
      if (err instanceof OnboardingIncompleteError) throw app.httpErrors.conflict(err.message);
      throw err;
    }
  });

  // Account deletion — one confirmation, cascading delete, Apple token revoke (§4).
  app.delete('/account', async (req) => {
    deleteBody.parse(req.body);
    try {
      return await deleteAccount({ prisma: getPrisma() }, (req as AuthedRequest).userId);
    } catch (err) {
      if (err instanceof AccountNotFoundError) throw app.httpErrors.notFound(err.message);
      throw err;
    }
  });
}
