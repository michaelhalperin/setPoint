import type { Goal } from '../engine/types.js';
import {
  ageFromBirthDate,
  computeCalorieTarget,
  computeProteinTarget,
  type ActivityLevel,
  type Sex,
} from './targets.js';

export type TargetInputs = {
  sex: Sex;
  birthDate: Date | null;
  heightCm: number | null;
  weightKg: number | null;
  activityLevel: ActivityLevel;
  goal: Goal;
  paceKgPerWeek: number;
};

/**
 * The daily kcal / protein targets implied by a profile (M16). Returns nulls
 * when body stats are incomplete — callers then keep an explicit target or
 * reject. Pace drives the surplus/deficit; MAINTAIN is neutral.
 */
export function deriveTargets(
  p: TargetInputs,
  now: Date = new Date(),
): { dailyKcalTarget: number | null; dailyProteinTargetG: number | null } {
  if (p.weightKg == null || p.heightCm == null || p.birthDate == null) {
    return { dailyKcalTarget: null, dailyProteinTargetG: null };
  }
  const stats = {
    sex: p.sex,
    weightKg: p.weightKg,
    heightCm: p.heightCm,
    ageYears: ageFromBirthDate(p.birthDate, now),
    activityLevel: p.activityLevel,
  };
  return {
    dailyKcalTarget: computeCalorieTarget(stats, p.goal, { paceKgPerWeek: p.paceKgPerWeek }),
    dailyProteinTargetG: computeProteinTarget(p.weightKg, p.goal),
  };
}
