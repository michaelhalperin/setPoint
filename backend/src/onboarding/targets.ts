import type { Goal } from '../engine/types.js';

export type Sex = 'MALE' | 'FEMALE' | 'UNSPECIFIED';
export type ActivityLevel = 'SEDENTARY' | 'LIGHT' | 'MODERATE' | 'ACTIVE' | 'VERY_ACTIVE';

const ACTIVITY_FACTOR: Record<ActivityLevel, number> = {
  SEDENTARY: 1.2,
  LIGHT: 1.375,
  MODERATE: 1.55,
  ACTIVE: 1.725,
  VERY_ACTIVE: 1.9,
};

// Fallback surplus / deficit when no pace is given (older clients). MAINTAIN is
// always neutral. The plan is about eating *enough*, not aggressive cuts.
const GOAL_KCAL_ADJUSTMENT: Record<Goal, number> = { BULK: 350, DIET: -400, MAINTAIN: 0 };
const GOAL_PROTEIN_PER_KG: Record<Goal, number> = { BULK: 1.8, DIET: 2.0, MAINTAIN: 1.6 };

/** ~7,700 kcal per kg of body mass — the standard energy-balance approximation. */
export const KCAL_PER_KG = 7700;

/**
 * Safety caps on how fast a goal may move (M16). A diet is capped as a fraction
 * of current body mass per week so it scales with the person; a bulk is capped
 * at a flat surplus. `clampPaceKgPerWeek` also floors a pace at a small positive
 * value so BULK/DIET always carry *some* adjustment.
 */
export const PACE_CAPS = {
  minKgPerWeek: 0.1,
  dietMaxFractionPerWeek: 0.0075, // 0.75 %/wk
  bulkMaxKgPerWeek: 0.5,
} as const;

export function clampPaceKgPerWeek(goal: Goal, weightKg: number | null, paceKgPerWeek: number): number {
  if (goal === 'MAINTAIN') return 0;
  const magnitude = Math.abs(paceKgPerWeek) || PACE_CAPS.minKgPerWeek;
  const ceiling =
    goal === 'DIET' && weightKg != null
      ? Math.max(PACE_CAPS.minKgPerWeek, weightKg * PACE_CAPS.dietMaxFractionPerWeek)
      : PACE_CAPS.bulkMaxKgPerWeek;
  return round2(Math.min(Math.max(magnitude, PACE_CAPS.minKgPerWeek), ceiling));
}

/**
 * The lowest BMI a weight target may imply — the WHO underweight cutoff.
 * SetPoint is about eating *enough* (§3); it never helps anyone diet below this.
 */
export const HEALTHY_BMI_FLOOR = 18.5;

/** Lowest healthy target weight for a height, rounded up to 0.1 kg. */
export function minHealthyWeightKg(heightCm: number): number {
  const meters = heightCm / 100;
  return Math.ceil(HEALTHY_BMI_FLOOR * meters * meters * 10) / 10;
}

export class UnhealthyTargetError extends Error {
  constructor(readonly minWeightKg: number) {
    super(`The lowest target I'll set for your height is ${minWeightKg} kg.`);
  }
}

/**
 * Throws UnhealthyTargetError when a DIET target sits below the healthy floor.
 * Only diets are checked: a gain target is above the current weight and
 * maintain has no target. Without a height there's nothing to check against.
 */
export function assertHealthyTarget(
  goal: Goal,
  targetWeightKg: number | null | undefined,
  heightCm: number | null | undefined,
): void {
  if (goal !== 'DIET' || targetWeightKg == null || heightCm == null) return;
  const min = minHealthyWeightKg(heightCm);
  if (targetWeightKg < min) throw new UnhealthyTargetError(min);
}

/** Signed daily calorie delta a pace implies for a goal. */
export function paceToKcalDelta(goal: Goal, paceKgPerWeek: number): number {
  if (goal === 'MAINTAIN') return 0;
  const perDay = Math.round((Math.abs(paceKgPerWeek) * KCAL_PER_KG) / 7);
  return goal === 'BULK' ? perDay : -perDay;
}

export type BodyStats = {
  sex: Sex;
  weightKg: number;
  heightCm: number;
  ageYears: number;
  activityLevel: ActivityLevel;
};

/** Mifflin–St Jeor resting metabolic rate. UNSPECIFIED sex uses the male/female mean. */
export function mifflinStJeorRmr(stats: BodyStats): number {
  const base = 10 * stats.weightKg + 6.25 * stats.heightCm - 5 * stats.ageYears;
  const sexOffset = stats.sex === 'MALE' ? 5 : stats.sex === 'FEMALE' ? -161 : -78;
  return base + sexOffset;
}

/**
 * Daily calorie target from stats + goal, rounded to the nearest 10.
 * When `paceKgPerWeek` is given the surplus/deficit is derived from it (M16);
 * otherwise the flat per-goal fallback is used.
 */
export function computeCalorieTarget(
  stats: BodyStats,
  goal: Goal,
  opts: { paceKgPerWeek?: number } = {},
): number {
  const tdee = mifflinStJeorRmr(stats) * ACTIVITY_FACTOR[stats.activityLevel];
  const delta =
    opts.paceKgPerWeek != null ? paceToKcalDelta(goal, opts.paceKgPerWeek) : GOAL_KCAL_ADJUSTMENT[goal];
  return Math.max(1200, Math.round((tdee + delta) / 10) * 10);
}

/** Daily protein target in grams from weight + goal. */
export function computeProteinTarget(weightKg: number, goal: Goal): number {
  return Math.round(weightKg * GOAL_PROTEIN_PER_KG[goal]);
}

export function ageFromBirthDate(birthDate: Date, now: Date = new Date()): number {
  let age = now.getUTCFullYear() - birthDate.getUTCFullYear();
  const m = now.getUTCMonth() - birthDate.getUTCMonth();
  if (m < 0 || (m === 0 && now.getUTCDate() < birthDate.getUTCDate())) age -= 1;
  return age;
}

const round2 = (n: number): number => Math.round(n * 100) / 100;
