/**
 * Closed-beta stop conditions, measured from real data. Only what the data can
 * show is evaluated here; allergy misses and unsafe copy are reported by people
 * and handled as manual release gates (BETA.md).
 */
export const STOP_CONFIG = {
  /** Look-back for delivery and feedback rates. */
  windowDays: 7,
  /** The score job runs every 15 min on GitHub Actions, which often runs late. */
  schedulerStaleMin: 45,
  /** Share of check-ins whose push failed or never went out. */
  maxDeliveryFailRate: 0.15,
  /** Wearable cohort worse than control by this much (absolute) halts the modifier. */
  maxWearableExcess: 0.1,
  /** Minimum check-ins per cohort before feedback rates are compared. */
  minCheckInsPerCohort: 20,
  /** Minimum users per cohort before pause rates are compared. */
  minUsersPerCohort: 10,
  /** Minimum check-ins before a delivery failure rate is trusted. */
  minCheckInsForDelivery: 10,
} as const;

export type Rate = { numerator: number; denominator: number };

export type StopSignals = {
  schedulerLastRunAt: Date | null;
  schedulerLastOk: boolean | null;
  /** FAILED, or never sent, over all check-ins created in the window. */
  delivery: Rate;
  /** "Already ate" / "wrong time" among check-ins scored with vs without the wearable. */
  negativeFeedback: { wearable: Rate; control: Rate };
  /** Users with check-ins paused, in the wearable cohort vs the rest. */
  paused: { wearable: Rate; control: Rate };
};

export type StopEvaluation = {
  /** Turn the wearable modifier off — the scoring job applies this on its own. */
  haltWearable: boolean;
  /** Needs a person now; nothing is switched off automatically. */
  alerts: string[];
  reasons: string[];
  rates: {
    deliveryFailRate: number | null;
    wearableNegativeRate: number | null;
    controlNegativeRate: number | null;
    wearablePauseRate: number | null;
    controlPauseRate: number | null;
  };
};

export function evaluateStopConditions(signals: StopSignals, now = new Date()): StopEvaluation {
  const reasons: string[] = [];
  const alerts: string[] = [];

  const stale =
    !signals.schedulerLastRunAt ||
    now.getTime() - signals.schedulerLastRunAt.getTime() > STOP_CONFIG.schedulerStaleMin * 60_000;
  if (stale) alerts.push('scheduler_stale');
  if (signals.schedulerLastOk === false) alerts.push('scheduler_failing');

  const deliveryFailRate = rate(signals.delivery, STOP_CONFIG.minCheckInsForDelivery);
  if (deliveryFailRate !== null && deliveryFailRate >= STOP_CONFIG.maxDeliveryFailRate) {
    alerts.push('delivery_failing');
  }

  const wearableNegativeRate = rate(signals.negativeFeedback.wearable, STOP_CONFIG.minCheckInsPerCohort);
  const controlNegativeRate = rate(signals.negativeFeedback.control, STOP_CONFIG.minCheckInsPerCohort);
  const wearablePauseRate = rate(signals.paused.wearable, STOP_CONFIG.minUsersPerCohort);
  const controlPauseRate = rate(signals.paused.control, STOP_CONFIG.minUsersPerCohort);

  let haltWearable = false;
  if (
    wearableNegativeRate !== null &&
    controlNegativeRate !== null &&
    wearableNegativeRate - controlNegativeRate >= STOP_CONFIG.maxWearableExcess
  ) {
    haltWearable = true;
    reasons.push('wearable_negative_feedback');
  }
  if (
    wearablePauseRate !== null &&
    controlPauseRate !== null &&
    wearablePauseRate - controlPauseRate >= STOP_CONFIG.maxWearableExcess
  ) {
    haltWearable = true;
    reasons.push('wearable_pauses');
  }

  return {
    haltWearable,
    alerts,
    reasons: [...reasons, ...alerts],
    rates: { deliveryFailRate, wearableNegativeRate, controlNegativeRate, wearablePauseRate, controlPauseRate },
  };
}

/** null until there is enough data to mean anything. */
function rate(r: Rate, minDenominator: number): number | null {
  if (r.denominator < minDenominator) return null;
  return Math.round((r.numerator / r.denominator) * 1000) / 1000;
}
