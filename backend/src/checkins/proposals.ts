export type PlanProposalKind = 'DELAY_CHECKINS' | 'EASE_TARGET' | 'PAUSE_CHECKINS';

export type PlanProposal = {
  kind: PlanProposalKind;
  title: string;
  summary: string;
  /** Minutes to shift meal times later (DELAY_CHECKINS). */
  delayMin?: number;
  /** kcal to subtract from the daily target (EASE_TARGET). */
  easeKcal?: number;
};

export const PROPOSALS: Record<PlanProposalKind, PlanProposal> = {
  DELAY_CHECKINS: {
    kind: 'DELAY_CHECKINS',
    title: 'Check in later',
    summary: 'Move breakfast, lunch and dinner 30 minutes later.',
    delayMin: 30,
  },
  EASE_TARGET: {
    kind: 'EASE_TARGET',
    title: 'Ease the target',
    summary: 'Lower your daily target by 150 kcal. Change it back anytime in Goal.',
    easeKcal: 150,
  },
  PAUSE_CHECKINS: {
    kind: 'PAUSE_CHECKINS',
    title: 'Pause check-ins',
    summary: 'Stop check-ins until you resume them in Settings.',
  },
};

export function proposalFromOutcome(outcome: string): PlanProposal | null {
  if (outcome === 'DELAY_CHECKINS') return PROPOSALS.DELAY_CHECKINS;
  if (outcome === 'EASE_TARGET' || outcome === 'ADJUST_PLAN') return PROPOSALS.EASE_TARGET;
  if (outcome === 'PAUSE_CHECKINS') return PROPOSALS.PAUSE_CHECKINS;
  return null;
}
