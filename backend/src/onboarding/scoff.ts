/**
 * SCOFF eating-disorder screen (plan §3): 5 validated yes/no questions,
 * ≥ 2 "yes" answers is a positive screen. A positive screen — or a self-reported
 * medical condition requiring supervised nutrition — disables the forcing
 * mechanism; the app becomes passive tracking only.
 */
export type ScoffAnswers = {
  /** Do you make yourself Sick because you feel uncomfortably full? */
  makeSelfSick: boolean;
  /** Do you worry you have lost Control over how much you eat? */
  lostControl: boolean;
  /** Have you recently lost more than One stone (~6.35 kg) in 3 months? */
  lostOneStone: boolean;
  /** Do you believe yourself to be Fat when others say you are too thin? */
  believesFat: boolean;
  /** Would you say Food dominates your life? */
  foodDominates: boolean;
};

export function scoffScore(answers: ScoffAnswers): number {
  return Object.values(answers).filter(Boolean).length;
}

export function scoffFlagged(answers: ScoffAnswers): boolean {
  return scoffScore(answers) >= 2;
}

export type EnforcementDecision =
  | { enforcementEnabled: true; enforcementDisabledReason: null }
  | {
      enforcementEnabled: false;
      enforcementDisabledReason: 'MEDICAL_SUPERVISION' | 'EATING_DISORDER_SCREEN';
    };

/** The single gate the confidence engine reads (`SafetyScreening.enforcementEnabled`). */
export function deriveEnforcement(
  medicalSupervisionRequired: boolean,
  scoffIsFlagged: boolean,
): EnforcementDecision {
  if (medicalSupervisionRequired) {
    return { enforcementEnabled: false, enforcementDisabledReason: 'MEDICAL_SUPERVISION' };
  }
  if (scoffIsFlagged) {
    return { enforcementEnabled: false, enforcementDisabledReason: 'EATING_DISORDER_SCREEN' };
  }
  return { enforcementEnabled: true, enforcementDisabledReason: null };
}
