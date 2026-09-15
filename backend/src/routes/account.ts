import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { AccountNotFoundError, deleteAccount } from '../account/deleteAccount.js';
import { requireAuth, type AuthedRequest } from '../auth/index.js';
import { OnboardingIncompleteError } from '../dashboard/home.js';
import { getPrisma } from '../db/client.js';
import { AlreadyOnboardedError, MissingTargetError, runOnboarding } from '../onboarding/onboard.js';
import { UnderageError } from '../onboarding/age.js';
import { getSettings, updateSettings } from '../onboarding/settings.js';
import { getPhotoStore } from '../photos/store.js';
import {
  acceptTargetReview,
  dismissTargetReview,
  NoTargetReviewError,
  StaleTargetReviewError,
  undoLastTargetReview,
} from '../weight/targetReview.js';

const minutes = z.number().int().min(0).max(1439);
const mealTimes = z.object({ breakfastMin: minutes, lunchMin: minutes, dinnerMin: minutes });
const weekendMealTimes = z.object({
  breakfastMin: minutes.nullable(),
  lunchMin: minutes.nullable(),
  dinnerMin: minutes.nullable(),
});
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
  preferredDurationWeeks: z.number().int().min(1).max(104).optional(),
  dailyKcalTarget: z.number().int().min(800).max(8000).optional(),
  dailyProteinTargetG: z.number().int().min(0).max(400).optional(),
  mealTimes: mealTimes.optional(),
  quietHours: quietHours.optional(),
  safety: z.object({
    medicalSupervisionRequired: z.boolean(),
    medicalConditionAffectsEating: z.boolean().optional(),
    scoff,
    restrictions: z.array(restriction).max(50).optional(),
    restrictionsFreeText: z.string().max(1000).optional(),
  }),
});

const settingsPatch = z
  .object({
    goal: z.enum(['BULK', 'DIET', 'MAINTAIN']).optional(),
    mode: z.enum(['BASIC', 'SMART']).optional(),
    targetWeightKg: z.number().positive().max(400).nullable().optional(),
    paceKgPerWeek: z.number().positive().max(2).optional(),
    preferredDurationWeeks: z.number().int().min(1).max(104).nullable().optional(),
    dailyKcalTarget: z.number().int().min(800).max(8000).optional(),
    dailyProteinTargetG: z.number().int().min(0).max(400).nullable().optional(),
    mealTimes: mealTimes.optional(),
    weekendMealTimes: weekendMealTimes.optional(),
    weekendDays: z.number().int().min(1).max(127).optional(),
    quietHours: quietHours.optional(),
    checkInsPaused: z.boolean().optional(),
    timezone: z.string().optional(),
    restrictions: z.array(restriction).max(50).optional(),
    pantryTokens: z.array(z.string().min(1).max(80)).max(40).optional(),
    dislikedFoods: z.array(z.string().min(1).max(80)).max(40).optional(),
    prepTimeMaxMin: z.number().int().min(0).max(240).nullable().optional(),
    healthWrite: z
      .object({
        energy: z.boolean(),
        protein: z.boolean(),
        carbs: z.boolean(),
        fat: z.boolean(),
        bodyMass: z.boolean(),
      })
      .optional(),
    calendar: z
      .object({
        enabled: z.boolean().optional(),
        leadMin: z.union([z.literal(30), z.literal(45), z.literal(60)]).optional(),
        minBlockMin: z.number().int().min(15).max(240).optional(),
        workdaysOnly: z.boolean().optional(),
        includeAllDay: z.boolean().optional(),
      })
      .optional(),
    training: z
      .object({
        addCalories: z.boolean().optional(),
        preWorkoutNudgeMin: z.union([z.literal(0), z.literal(60), z.literal(90), z.literal(120), z.null()]).optional(),
      })
      .optional(),
    appetite: z
      .object({
        mode: z.enum(['NORMAL', 'SMALL_FREQUENT']).optional(),
        drinkableOk: z.boolean().optional(),
        askDaily: z.boolean().optional(),
      })
      .optional(),
  })
  .refine((p) => Object.keys(p).length > 0, { message: 'no changes provided' });

// The server computes the suggestion; the client only says what it decided and
// which proposed target it saw.
const targetReviewBody = z.discriminatedUnion('action', [
  z.object({ action: z.literal('accept'), proposedKcal: z.number().int() }),
  z.object({ action: z.literal('dismiss') }),
  z.object({ action: z.literal('undo') }),
]);

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
      if (err instanceof UnderageError) throw app.httpErrors.forbidden(err.message);
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

  app.post('/settings/target-review', async (req) => {
    const body = targetReviewBody.parse(req.body);
    const userId = (req as AuthedRequest).userId;
    const prisma = getPrisma();
    try {
      switch (body.action) {
        case 'accept':
          return { action: body.action, ...(await acceptTargetReview(prisma, userId, body.proposedKcal)) };
        case 'dismiss':
          await dismissTargetReview(prisma, userId);
          return { action: body.action };
        case 'undo':
          return { action: body.action, ...(await undoLastTargetReview(prisma, userId)) };
      }
    } catch (err) {
      if (err instanceof NoTargetReviewError || err instanceof StaleTargetReviewError) {
        throw app.httpErrors.conflict(err.message);
      }
      throw err;
    }
  });

  // Account deletion — one confirmation, cascading delete, Apple token revoke (§4).
  app.delete('/account', async (req) => {
    deleteBody.parse(req.body);
    try {
      return await deleteAccount(
        { prisma: getPrisma(), photos: getPhotoStore() },
        (req as AuthedRequest).userId,
      );
    } catch (err) {
      if (err instanceof AccountNotFoundError) throw app.httpErrors.notFound(err.message);
      throw err;
    }
  });
}
