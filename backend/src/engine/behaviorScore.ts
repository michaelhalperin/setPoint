import { clamp } from './types.js';

/** Versioned, auditable behavior score. Wearable data is a capped modifier only. */
export const SCORING_VERSION = 'behavior.v1';

export const SCORE_CONFIG = {
  /** Fire when the combined score clears this, and only if a meal is already due. */
  threshold: 0.45,
  /** Minutes overdue at which the overdue component saturates. */
  overdueFullMin: 90,
  /** Maximum the wearable may add when it agrees with under-fueling. */
  maxWearableBoost: 0.15,
  /** Maximum the wearable may subtract when it disagrees. Never enough to be the sole trigger. */
  maxWearableCut: 0.1,
  loggingWindow: 14,
} as const;

export type RecentCheckIn = {
  status: string;
  feedbackPositive: boolean | null;
  deferCount: number;
};

export type WearableInput = {
  hrvDeviation: number;
  rhrDeviation: number | null;
};

export type BehaviorScoreInput = {
  overdueMin: number;
  hoursSinceMeal: number;
  expectedGapHours: number;
  consumedKcal: number;
  targetKcal: number;
  recentCheckIns: RecentCheckIn[];
  wearable: WearableInput | null;
  /** Kill switch + cohort. False ⇒ modifier 0, identical to Basic. */
  wearableEnabled: boolean;
};

export type ScoreComponents = {
  overdue: number;
  gap: number;
  coverage: number;
  reliability: number;
  dismissRate: number;
  deferRate: number;
};

export type BehaviorScoreResult = {
  version: typeof SCORING_VERSION;
  behaviorScore: number;
  wearableModifier: number;
  wearableUsed: boolean;
  score: number;
  threshold: number;
  shouldFire: boolean;
  components: ScoreComponents;
};

/**
 * Pure behavior-led score. A check-in is eligible only when the caller has
 * already established that a meal slot is overdue; this function never
 * diagnoses under-fueling from HRV/RHR alone.
 */
export function computeBehaviorScore(input: BehaviorScoreInput): BehaviorScoreResult {
  const overdue = clamp(input.overdueMin / SCORE_CONFIG.overdueFullMin, 0, 1);
  const gap =
    input.expectedGapHours > 0 ? clamp(input.hoursSinceMeal / input.expectedGapHours, 0, 1) : 0.5;
  const coverageRatio = input.targetKcal > 0 ? clamp(input.consumedKcal / input.targetKcal, 0, 1.2) : 0;
  const coverage = clamp(1 - coverageRatio, 0, 1);

  const history = input.recentCheckIns.slice(0, SCORE_CONFIG.loggingWindow);
  const n = history.length;
  let misses = 0;
  let dismissals = 0;
  let deferred = 0;
  for (const c of history) {
    if (c.status === 'EXPIRED' || c.status === 'ESCALATED') misses += 1;
    if (c.status === 'EXPIRED' && c.feedbackPositive === false) dismissals += 1;
    if (c.deferCount > 0) deferred += 1;
  }
  const reliability = n === 0 ? 1 : clamp(1 - misses / n, 0, 1);
  const dismissRate = n === 0 ? 0 : dismissals / n;
  const deferRate = n === 0 ? 0 : deferred / n;

  const behaviorScore = clamp(
    0.4 * overdue +
      0.25 * gap +
      0.25 * coverage +
      0.1 * reliability -
      0.15 * dismissRate -
      0.05 * deferRate,
    0,
    1,
  );

  const { wearableModifier, wearableUsed } = wearableAdjustment(input.wearable, input.wearableEnabled);
  const score = clamp(behaviorScore + wearableModifier, 0, 1);

  return {
    version: SCORING_VERSION,
    behaviorScore: round3(behaviorScore),
    wearableModifier: round3(wearableModifier),
    wearableUsed,
    score: round3(score),
    threshold: SCORE_CONFIG.threshold,
    shouldFire: score >= SCORE_CONFIG.threshold,
    components: {
      overdue: round3(overdue),
      gap: round3(gap),
      coverage: round3(coverage),
      reliability: round3(reliability),
      dismissRate: round3(dismissRate),
      deferRate: round3(deferRate),
    },
  };
}

function wearableAdjustment(
  wearable: WearableInput | null,
  enabled: boolean,
): { wearableModifier: number; wearableUsed: boolean } {
  if (!enabled || !wearable) return { wearableModifier: 0, wearableUsed: false };
  if (!Number.isFinite(wearable.hrvDeviation)) return { wearableModifier: 0, wearableUsed: false };

  const rhr = Number.isFinite(wearable.rhrDeviation) ? (wearable.rhrDeviation as number) : 0;
  // Negative HRV + positive RHR = under-fueling direction. Combined and capped.
  const underFueling = clamp((-wearable.hrvDeviation + rhr) / 2, -1, 1);
  const modifier =
    underFueling >= 0
      ? underFueling * SCORE_CONFIG.maxWearableBoost
      : underFueling * SCORE_CONFIG.maxWearableCut;
  return { wearableModifier: modifier, wearableUsed: true };
}

export function expectedGapHours(
  slot: 'breakfast' | 'lunch' | 'dinner',
  times: { breakfastMin: number; lunchMin: number; dinnerMin: number },
): number {
  if (slot === 'breakfast') return times.breakfastMin / 60 || 8;
  if (slot === 'lunch') return (times.lunchMin - times.breakfastMin) / 60;
  return (times.dinnerMin - times.lunchMin) / 60;
}

function round3(n: number): number {
  return Math.round(n * 1000) / 1000;
}
