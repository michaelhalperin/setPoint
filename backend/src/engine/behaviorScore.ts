import type { SlotName } from './mealSchedule.js';
import { clamp } from './types.js';

/**
 * Versioned, auditable decision for a meal that is already overdue: fire the
 * check-in now, or hold it for a later run. Wearable data is a capped modifier
 * only — it can never fire a check-in on its own.
 */
export const SCORING_VERSION = 'behavior.v2';

export const SCORE_CONFIG = {
  /** Fire when the combined score reaches this. */
  threshold: 0.5,
  weights: {
    /** Behind the day's pace (the strongest evidence). */
    behind: 0.45,
    /** Long since the last meal, relative to this user's usual gap. */
    gap: 0.25,
    /** Minutes past the due time — holding gets harder the longer it runs. */
    overdue: 0.3,
    /** This meal's check-ins were often "already ate" / "wrong time". */
    slotDismissals: 0.25,
  },
  /** Minutes past due at which the overdue component saturates. */
  overdueFullMin: 90,
  /** A gap this many times the usual one counts as fully long. */
  gapFullRatio: 1.5,
  /** How many of this meal's recent check-ins inform the dismissal rate. */
  slotHistory: 10,
  /** Maximum the wearable may add when it agrees with under-fueling. */
  maxWearableBoost: 0.15,
  /** Maximum the wearable may subtract when it disagrees. */
  maxWearableCut: 0.1,
} as const;

/** Share of the daily target a user on pace has eaten once each meal is done. */
const EXPECTED_SHARE_THROUGH: Record<SlotName, number> = {
  breakfast: 1 / 3,
  lunch: 2 / 3,
  dinner: 1,
  snack_am: 0.45,
  snack_pm: 0.8,
};

export type RecentCheckIn = {
  status: string;
  feedbackPositive: boolean | null;
};

export type WearableInput = {
  hrvDeviation: number;
  rhrDeviation: number | null;
};

export type BehaviorScoreInput = {
  slot: SlotName;
  overdueMin: number;
  hoursSinceMeal: number;
  expectedGapHours: number;
  consumedKcal: number;
  targetKcal: number;
  /** This slot's recent check-ins, newest first. */
  slotCheckIns: RecentCheckIn[];
  wearable: WearableInput | null;
  /** Kill switch + cohort. False ⇒ modifier 0, identical to Basic. */
  wearableEnabled: boolean;
};

export type ScoreComponents = {
  /** 0 = on pace for this meal, 1 = a full meal (or more) behind. */
  behind: number;
  gap: number;
  overdue: number;
  slotDismissRate: number;
  /** Raw inputs kept alongside the components. */
  consumedShare: number;
  expectedShare: number;
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

export function computeBehaviorScore(input: BehaviorScoreInput): BehaviorScoreResult {
  const { weights } = SCORE_CONFIG;
  const expectedShare = EXPECTED_SHARE_THROUGH[input.slot];
  const consumedShare = input.targetKcal > 0 ? input.consumedKcal / input.targetKcal : 0;
  // One meal is a third of the day: being a whole meal short saturates.
  const behind = clamp((expectedShare - consumedShare) / (1 / 3), 0, 1);

  const gap =
    input.expectedGapHours > 0
      ? clamp(input.hoursSinceMeal / input.expectedGapHours / SCORE_CONFIG.gapFullRatio, 0, 1)
      : 0.5;
  const overdue = clamp(input.overdueMin / SCORE_CONFIG.overdueFullMin, 0, 1);

  const history = input.slotCheckIns.slice(0, SCORE_CONFIG.slotHistory);
  const dismissed = history.filter((c) => c.feedbackPositive === false).length;
  const slotDismissRate = history.length === 0 ? 0 : dismissed / history.length;

  const behaviorScore = clamp(
    weights.behind * behind + weights.gap * gap + weights.overdue * overdue - weights.slotDismissals * slotDismissRate,
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
      behind: round3(behind),
      gap: round3(gap),
      overdue: round3(overdue),
      slotDismissRate: round3(slotDismissRate),
      consumedShare: round3(consumedShare),
      expectedShare: round3(expectedShare),
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
  slot: SlotName,
  times: { breakfastMin: number; lunchMin: number; dinnerMin: number },
): number {
  // Breakfast follows the overnight gap since dinner.
  if (slot === 'breakfast') return (24 * 60 - times.dinnerMin + times.breakfastMin) / 60;
  if (slot === 'lunch') return (times.lunchMin - times.breakfastMin) / 60;
  return (times.dinnerMin - times.lunchMin) / 60;
}

function round3(n: number): number {
  return Math.round(n * 1000) / 1000;
}
