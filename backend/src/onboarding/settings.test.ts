import type { PrismaClient } from '@prisma/client';
import { describe, expect, it } from 'vitest';
import { OnboardingIncompleteError } from '../dashboard/home.js';
import { getSettings, updateSettings } from './settings.js';

type AnyRow = Record<string, unknown>;

function fakePrisma(user: AnyRow | null) {
  const restrictions: AnyRow[] = (user?.restrictions as AnyRow[]) ?? [];
  const state = { user, restrictions };

  const prisma = {
    __state: state,
    user: {
      findUnique: async () =>
        state.user
          ? {
              ...state.user,
              restrictions: state.restrictions,
              weightEntries: (state.user.weightEntries as AnyRow[]) ?? [],
            }
          : null,
      update: async ({ data }: { data: AnyRow }) => {
        if (state.user) Object.assign(state.user, data);
        return state.user;
      },
    },
    onboardingProfile: {
      findUnique: async () => ((state.user as AnyRow)?.onboarding as AnyRow) ?? null,
      update: async ({ data }: { data: AnyRow }) => {
        Object.assign((state.user as AnyRow).onboarding as AnyRow, data);
        return (state.user as AnyRow).onboarding;
      },
    },
    weightEntry: {
      findFirst: async () => ((state.user as AnyRow)?.weightEntries as AnyRow[])?.[0] ?? null,
    },
    escalationState: {
      upsert: async ({ create, update }: { create: AnyRow; update: AnyRow }) => {
        (state.user as AnyRow).escalationState = {
          ...((state.user as AnyRow).escalationState as AnyRow),
          ...create,
          ...update,
        };
        return (state.user as AnyRow).escalationState;
      },
    },
    dietaryRestriction: {
      deleteMany: async () => {
        const count = restrictions.length;
        restrictions.length = 0;
        return { count };
      },
      createMany: async ({ data }: { data: AnyRow[] }) => {
        restrictions.push(...data);
        return { count: data.length };
      },
    },
    $transaction: async (fn: (tx: unknown) => Promise<unknown>) => fn(prisma),
  };
  return prisma as unknown as PrismaClient & { __state: typeof state };
}

const onboardedUser = (): AnyRow => ({
  id: 'u1',
  timezone: 'America/New_York',
  onboarding: {
    goal: 'DIET',
    mode: 'BASIC',
    dailyKcalTarget: 2200,
    dailyProteinTargetG: 160,
    breakfastMin: 480,
    lunchMin: 780,
    dinnerMin: 1140,
    quietHoursStartMin: 1380,
    quietHoursEndMin: 420,
  },
  safetyScreening: { enforcementEnabled: true, enforcementDisabledReason: null },
  escalationState: { checkInsPaused: false },
  restrictions: [{ label: 'Dairy', token: 'dairy', source: 'INTOLERANCE' }],
});

describe('settings', () => {
  it('returns the current settings view', async () => {
    const view = await getSettings({ prisma: fakePrisma(onboardedUser()) }, 'u1');
    expect(view).toMatchObject({
      goal: 'DIET',
      dailyKcalTarget: 2200,
      quietHours: { startMin: 1380, endMin: 420 },
      checkInsPaused: false,
    });
    expect(view.restrictions).toEqual([{ label: 'Dairy', token: 'dairy', source: 'INTOLERANCE' }]);
  });

  it('updates quiet hours and the pause toggle', async () => {
    const prisma = fakePrisma(onboardedUser());
    const view = await updateSettings({ prisma }, 'u1', {
      quietHours: { startMin: 1320, endMin: 480 },
      checkInsPaused: true,
    });
    expect(view.quietHours).toEqual({ startMin: 1320, endMin: 480 });
    expect(view.checkInsPaused).toBe(true);
  });

  it('replaces the restriction set, normalizing tokens', async () => {
    const prisma = fakePrisma(onboardedUser());
    const view = await updateSettings({ prisma }, 'u1', {
      restrictions: [{ label: 'Tree Nuts' }, { label: 'tree nuts' }, { label: 'Gluten', source: 'MEDICAL' }],
    });
    expect(view.restrictions.map((r) => r.token).sort()).toEqual(['gluten', 'tree_nut']);
  });

  it('rejects settings for a user who has not onboarded', async () => {
    await expect(getSettings({ prisma: fakePrisma(null) }, 'u1')).rejects.toBeInstanceOf(OnboardingIncompleteError);
  });
});
