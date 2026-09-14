import type { Prisma } from '@prisma/client';
import { describe, expect, it } from 'vitest';
import { applyPlanProposal, ProposalNotApplicableError } from './applyProposal.js';

function fakeTx(profile: { breakfastMin: number; lunchMin: number; dinnerMin: number; dailyKcalTarget: number }) {
  const state = { profile: { ...profile }, paused: false };
  const tx = {
    escalationState: {
      upsert: async () => {
        state.paused = true;
      },
    },
    onboardingProfile: {
      findUnique: async () => state.profile,
      update: async ({ data }: { data: Partial<typeof profile> }) => Object.assign(state.profile, data),
    },
  };
  return { tx: tx as unknown as Prisma.TransactionClient, state };
}

const PROFILE = { breakfastMin: 480, lunchMin: 780, dinnerMin: 1140, dailyKcalTarget: 2600 };

describe('applyPlanProposal', () => {
  it('moves all three meals 30 minutes later', async () => {
    const { tx, state } = fakeTx(PROFILE);
    await applyPlanProposal(tx, 'u1', 'DELAY_CHECKINS');
    expect(state.profile).toMatchObject({ breakfastMin: 510, lunchMin: 810, dinnerMin: 1170 });
  });

  it('refuses to push dinner past midnight instead of squashing the times', async () => {
    const { tx, state } = fakeTx({ ...PROFILE, dinnerMin: 1420 });
    await expect(applyPlanProposal(tx, 'u1', 'DELAY_CHECKINS')).rejects.toBeInstanceOf(ProposalNotApplicableError);
    expect(state.profile.dinnerMin).toBe(1420);
  });

  it('lowers the target by 150, but never below the floor', async () => {
    const { tx, state } = fakeTx(PROFILE);
    await applyPlanProposal(tx, 'u1', 'EASE_TARGET');
    expect(state.profile.dailyKcalTarget).toBe(2450);

    const low = fakeTx({ ...PROFILE, dailyKcalTarget: 1300 });
    await expect(applyPlanProposal(low.tx, 'u1', 'EASE_TARGET')).rejects.toBeInstanceOf(ProposalNotApplicableError);
    expect(low.state.profile.dailyKcalTarget).toBe(1300);
  });

  it('pauses check-ins', async () => {
    const { tx, state } = fakeTx(PROFILE);
    await applyPlanProposal(tx, 'u1', 'PAUSE_CHECKINS');
    expect(state.paused).toBe(true);
  });
});
