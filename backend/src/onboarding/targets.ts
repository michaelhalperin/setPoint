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
