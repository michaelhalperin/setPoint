import type { Prisma } from '@prisma/client';
import { MIN_DAILY_KCAL } from '../onboarding/targets.js';
import { PROPOSALS, type PlanProposal, type PlanProposalKind } from './proposals.js';

/** Thrown when a proposal can't be applied as described (e.g. dinner would pass midnight). */
export class ProposalNotApplicableError extends Error {}

/** Applies a confirmed proposal. Pass the transaction so it lands with the conversation update. */
export async function applyPlanProposal(
  tx: Prisma.TransactionClient,
  userId: string,
  kind: PlanProposalKind,
): Promise<PlanProposal> {
  const proposal = PROPOSALS[kind];

  if (kind === 'PAUSE_CHECKINS') {
    await tx.escalationState.upsert({
      where: { userId },
      create: { userId, checkInsPaused: true },
      update: { checkInsPaused: true },
    });
    return proposal;
  }

  const profile = await tx.onboardingProfile.findUnique({ where: { userId } });
  if (!profile) throw new ProposalNotApplicableError('onboarding not complete');

  if (kind === 'DELAY_CHECKINS') {
    const shift = proposal.delayMin ?? 30;
    if (profile.dinnerMin + shift > 1439) {
      throw new ProposalNotApplicableError('dinner is already as late as it can go');
    }
    await tx.onboardingProfile.update({
      where: { userId },
      data: {
        breakfastMin: profile.breakfastMin + shift,
        lunchMin: profile.lunchMin + shift,
        dinnerMin: profile.dinnerMin + shift,
      },
    });
    return proposal;
  }

  // EASE_TARGET
  const eased = profile.dailyKcalTarget - (proposal.easeKcal ?? 150);
  if (eased < MIN_DAILY_KCAL) {
    throw new ProposalNotApplicableError('the target is already at its floor');
  }
  await tx.onboardingProfile.update({ where: { userId }, data: { dailyKcalTarget: eased } });
  return proposal;
}
