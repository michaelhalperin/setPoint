import type { PrismaClient } from '@prisma/client';
import { hoursBetween, startOfLocalDay, type Goal } from '../engine/index.js';
import type { ManagerVoice } from '../managerVoice/types.js';
import { homeFraming, type FramingState } from './classify.js';

export type HomeDeps = {
  prisma: PrismaClient;
  voice: ManagerVoice;
  now?: Date;
};

export type HomeView = {
  goal: Goal;
  mode: string;
  enforcementEnabled: boolean;
  ledger: {
    consumedKcal: number;
    targetKcal: number;
    remainingKcal: number;
    consumedProteinG: number;
    targetProteinG: number | null;
    remainingProteinG: number | null;
    mealsToday: number;
    lastMealAt: string | null;
  };
  framing: {
    state: FramingState;
    accent: boolean;
    primaryCta: 'log_meal' | null;
    heroKcal: number;
  };
  managerNote: string;
  activeCheckIn: null | {
    id: string;
    tier: number;
    status: string;
    message: string | null;
    deferUntil: string | null;
    prescription: null | {
      id: string;
      totalKcal: number;
      totalProteinG: number;
      items: { name: string; quantity: number; kcal: number; proteinG: number }[];
    };
  };
};

const round1 = (n: number): number => Math.round(n * 10) / 10;

export class OnboardingIncompleteError extends Error {}

export async function buildHome(deps: HomeDeps, userId: string): Promise<HomeView> {
  const now = deps.now ?? new Date();
  const { prisma } = deps;

  const user = await prisma.user.findUnique({
    where: { id: userId },
    include: { onboarding: true, safetyScreening: true },
  });
  if (!user?.onboarding) throw new OnboardingIncompleteError('onboarding not complete');

  const profile = user.onboarding;
  const dayStart = startOfLocalDay(now, user.timezone);

  const [todayMeals, lastMeal, activeCheckIn] = await Promise.all([
    prisma.meal.findMany({
      where: { userId, loggedAt: { gte: dayStart } },
      select: { kcal: true, proteinG: true },
    }),
    prisma.meal.findFirst({ where: { userId }, orderBy: { loggedAt: 'desc' }, select: { loggedAt: true } }),
    prisma.checkIn.findFirst({
      where: { userId, status: { in: ['PENDING', 'DEFERRED'] } },
      orderBy: { createdAt: 'desc' },
      include: { prescription: { include: { items: true } } },
    }),
  ]);

  const consumedKcal = todayMeals.reduce((acc, m) => acc + m.kcal, 0);
  const consumedProteinG = round1(todayMeals.reduce((acc, m) => acc + m.proteinG, 0));
  const targetKcal = profile.dailyKcalTarget;
  const targetProteinG = profile.dailyProteinTargetG;
  const goal = profile.goal as Goal;

  const framing = homeFraming(goal, consumedKcal, targetKcal);
  const remainingKcal = Math.round(targetKcal - consumedKcal);
  const hoursSinceMeal = lastMeal ? hoursBetween(lastMeal.loggedAt, now) : null;

  const managerNote = await deps.voice.homeNote({
    goal,
    state: framing.state,
    consumedKcal,
    targetKcal,
    remainingKcal,
    hoursSinceMeal,
    hasActiveCheckIn: activeCheckIn !== null,
  });

  return {
    goal,
    mode: profile.mode,
    enforcementEnabled: user.safetyScreening?.enforcementEnabled ?? false,
    ledger: {
      consumedKcal,
      targetKcal,
      remainingKcal,
      consumedProteinG,
      targetProteinG,
      remainingProteinG: targetProteinG === null ? null : round1(targetProteinG - consumedProteinG),
      mealsToday: todayMeals.length,
      lastMealAt: lastMeal?.loggedAt.toISOString() ?? null,
    },
    framing: {
      state: framing.state,
      accent: framing.accent,
      primaryCta: framing.primaryCta,
      heroKcal: framing.heroKcal,
    },
    managerNote,
    activeCheckIn: activeCheckIn
      ? {
          id: activeCheckIn.id,
          tier: activeCheckIn.tier,
          status: activeCheckIn.status,
          message: activeCheckIn.message,
          deferUntil: activeCheckIn.deferUntil?.toISOString() ?? null,
          prescription: activeCheckIn.prescription
            ? {
                id: activeCheckIn.prescription.id,
                totalKcal: activeCheckIn.prescription.totalKcal,
                totalProteinG: activeCheckIn.prescription.totalProteinG,
                items: activeCheckIn.prescription.items.map((i) => ({
                  name: i.name,
                  quantity: i.quantity,
                  kcal: i.kcal,
                  proteinG: i.proteinG,
                })),
              }
            : null,
        }
      : null,
  };
}
