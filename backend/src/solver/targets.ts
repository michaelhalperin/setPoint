import { clamp } from '../engine/types.js';
import { SOLVER_CONFIG, type SolverConfig } from './config.js';

export type DailyIntake = {
  dailyKcalTarget: number;
  consumedKcal: number;
  dailyProteinTargetG: number | null;
  consumedProteinG: number;
};

/**
 * Turns the day's remaining gap into a single meal-sized target for the solver.
 * A prescription never tries to close the whole day's deficit at once.
 */
export function computePrescriptionTarget(
  intake: DailyIntake,
  config: SolverConfig = SOLVER_CONFIG,
): { targetKcal: number; targetProteinG: number | null } {
  const remainingKcal = Math.max(0, intake.dailyKcalTarget - intake.consumedKcal);
  const targetKcal = clamp(remainingKcal, config.minMealKcal, config.maxMealKcal);

  let targetProteinG: number | null = null;
  if (intake.dailyProteinTargetG && intake.dailyProteinTargetG > 0) {
    const remainingProtein = Math.max(0, intake.dailyProteinTargetG - intake.consumedProteinG);
    targetProteinG = Math.min(remainingProtein, config.maxProteinPerMeal);
  }

  return { targetKcal, targetProteinG };
}
