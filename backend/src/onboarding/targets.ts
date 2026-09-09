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

// Modest surplus / deficit — the plan is about eating *enough*, not aggressive cuts.
const GOAL_KCAL_ADJUSTMENT: Record<Goal, number> = { BULK: 350, DIET: -400 };
const GOAL_PROTEIN_PER_KG: Record<Goal, number> = { BULK: 1.8, DIET: 2.0 };

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

/** Daily calorie target from stats + goal, rounded to the nearest 10. */
export function computeCalorieTarget(stats: BodyStats, goal: Goal): number {
  const tdee = mifflinStJeorRmr(stats) * ACTIVITY_FACTOR[stats.activityLevel];
  return Math.max(1200, Math.round((tdee + GOAL_KCAL_ADJUSTMENT[goal]) / 10) * 10);
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
