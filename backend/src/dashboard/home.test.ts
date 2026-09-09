import type { PrismaClient } from '@prisma/client';
import { describe, expect, it, vi } from 'vitest';
import type { ManagerVoice } from '../managerVoice/types.js';
import { OnboardingIncompleteError, buildHome } from './home.js';

const NOW = new Date('2026-09-01T18:00:00Z'); // 14:00 in New York
const hoursAgo = (h: number) => new Date(NOW.getTime() - h * 3_600_000);

const voice: ManagerVoice = {
  checkInMessage: vi.fn(async () => 'ci'),
  homeNote: vi.fn(async () => 'MANAGER NOTE'),
  daySummary: vi.fn(async () => 'ds'),
};

type AnyRow = Record<string, unknown>;

function fakePrisma(over: { user?: AnyRow | null; meals?: AnyRow[]; checkIn?: AnyRow | null } = {}) {
  const meals = over.meals ?? [];
  return {
    user: { findUnique: async () => (over.user === undefined ? defaultUser : over.user) },
    meal: {
      findMany: async ({ where }: { where?: AnyRow }) => {
        const gte = (where?.loggedAt as { gte?: Date } | undefined)?.gte;
        return gte ? meals.filter((m) => (m.loggedAt as Date) >= gte) : meals;
      },
      findFirst: async () =>
        [...meals].sort((a, b) => (b.loggedAt as Date).getTime() - (a.loggedAt as Date).getTime())[0] ?? null,
    },
    checkIn: { findFirst: async () => over.checkIn ?? null },
  } as unknown as PrismaClient;
}

const defaultUser: AnyRow = {
  id: 'u1',
  timezone: 'America/New_York',
  onboarding: { goal: 'BULK', mode: 'SMART', dailyKcalTarget: 3000, dailyProteinTargetG: 180 },
  safetyScreening: { enforcementEnabled: true },
};

describe('buildHome', () => {
  it('sums today\'s ledger and frames a bulk deficit with the accent', async () => {
    const prisma = fakePrisma({
      meals: [
        { loggedAt: hoursAgo(5), kcal: 600, proteinG: 30 },
        { loggedAt: hoursAgo(2), kcal: 700, proteinG: 45 },
      ],
    });

    const view = await buildHome({ prisma, voice, now: NOW }, 'u1');

    expect(view.goal).toBe('BULK');
    expect(view.ledger.consumedKcal).toBe(1300);
    expect(view.ledger.remainingKcal).toBe(1700);
    expect(view.ledger.consumedProteinG).toBe(75);
    expect(view.ledger.remainingProteinG).toBe(105);
    expect(view.ledger.mealsToday).toBe(2);
    expect(view.framing).toMatchObject({ state: 'under', accent: true, primaryCta: 'log_meal', heroKcal: 1700 });
    expect(view.managerNote).toBe('MANAGER NOTE');
  });

  it('gives going over a quiet, neutral treatment', async () => {
    const prisma = fakePrisma({ meals: [{ loggedAt: hoursAgo(1), kcal: 3400, proteinG: 200 }] });
    const view = await buildHome({ prisma, voice, now: NOW }, 'u1');
    expect(view.framing).toMatchObject({ state: 'over', accent: false, primaryCta: null });
  });

  it('surfaces an active check-in and its prescription', async () => {
    const prisma = fakePrisma({
      meals: [],
      checkIn: {
        id: 'ci_1',
        tier: 2,
        status: 'PENDING',
        message: 'eat now',
        deferUntil: null,
        prescription: {
          id: 'rx_1',
          totalKcal: 450,
          totalProteinG: 40,
          items: [{ name: 'Cottage cheese', quantity: 2, kcal: 388, proteinG: 54 }],
        },
      },
    });

    const view = await buildHome({ prisma, voice, now: NOW }, 'u1');
    expect(view.activeCheckIn?.id).toBe('ci_1');
    expect(view.activeCheckIn?.prescription?.items[0]?.name).toBe('Cottage cheese');
  });

  it('rejects a user who has not finished onboarding', async () => {
    await expect(
      buildHome({ prisma: fakePrisma({ user: { id: 'u1', timezone: 'UTC', onboarding: null } }), voice, now: NOW }, 'u1'),
    ).rejects.toBeInstanceOf(OnboardingIncompleteError);
  });
});
