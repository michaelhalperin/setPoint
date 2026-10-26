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

const PROPOSALS_HE: Record<PlanProposalKind, { title: string; summary: string }> = {
  DELAY_CHECKINS: { title: 'תזכורת מאוחר יותר', summary: 'להזיז את ארוחת הבוקר, הצהריים והערב ב-30 דקות אחורה.' },
  EASE_TARGET: { title: 'להקל על היעד', summary: 'להוריד את היעד היומי ב-150 קלוריות. אפשר להחזיר בכל עת במטרה.' },
  PAUSE_CHECKINS: { title: 'להשהות תזכורות', summary: 'להפסיק את התזכורות עד שתחזור אליהן בהגדרות.' },
};

/** A proposal's wording in the user's language. */
export function localizedProposal(proposal: PlanProposal, lang: 'en' | 'he'): PlanProposal {
  return lang === 'he' ? { ...proposal, ...PROPOSALS_HE[proposal.kind] } : proposal;
}

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
