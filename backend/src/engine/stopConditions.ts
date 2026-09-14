/**
 * Closed-beta stop conditions. Any true flag means the affected feature
 * must be disabled immediately (wearable modifier, scoring, or the whole
 * intervention path) rather than tuned in place.
 */
export type StopConditionFlags = {
  disableWearableIfOptOutUp: boolean;
  disableScoringIfDeliveryFailing: boolean;
  allergyMissIsP0: boolean;
  unsafeCopyIsP0: boolean;
  retentionDropDisablesFeature: boolean;
};

export const BETA_STOP_CONDITIONS: StopConditionFlags = {
  disableWearableIfOptOutUp: true,
  disableScoringIfDeliveryFailing: true,
  allergyMissIsP0: true,
  unsafeCopyIsP0: true,
  retentionDropDisablesFeature: true,
};

export type StopEvaluationInput = {
  wearableEnabled: boolean;
  schedulerStale: boolean;
  deliveryFailRate: number;
  optOutRate: number;
};

export type StopEvaluation = {
  disableWearable: boolean;
  disableScoring: boolean;
  reasons: string[];
};

export function evaluateStopConditions(input: StopEvaluationInput): StopEvaluation {
  const reasons: string[] = [];
  let disableWearable = false;
  let disableScoring = false;

  if (input.schedulerStale || input.deliveryFailRate >= 0.15) {
    disableScoring = true;
    reasons.push('delivery_failing');
  }
  if (input.wearableEnabled && input.optOutRate >= 0.2) {
    disableWearable = true;
    reasons.push('wearable_opt_out');
  }

  return { disableWearable, disableScoring, reasons };
}
