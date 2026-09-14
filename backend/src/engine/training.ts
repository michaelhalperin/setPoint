import { MIN_DAILY_KCAL } from '../onboarding/targets.js';

export const TRAINING_VERSION = 'training.v1';
export const TRAINING_BUMP_CAP = 800;
export const TRAINING_ROUND = 50;
export const REFUEL_WINDOW_MIN = 45;
export const REFUEL_MIN_KCAL = 250;
export const PRE_WORKOUT_LOOKBACK_MIN = 180;

export type WorkoutKind = 'STRENGTH' | 'CARDIO' | 'MIXED';
export type WorkoutSource = 'HEALTHKIT' | 'PLANNED';

export type TrainingWorkout = {
  source: WorkoutSource;
  kind: WorkoutKind;
  start: Date;
  durationMin: number;
  activeKcal: number | null;
};

const MET: Record<WorkoutKind, number> = {
  STRENGTH: 6,
  CARDIO: 8,
  MIXED: 7,
};

/** Net training kcal for one session. HealthKit active energy wins when present. */
export function sessionKcal(workout: TrainingWorkout, weightKg: number): number {
  if (workout.activeKcal != null && workout.activeKcal > 0) return workout.activeKcal;
  const hours = Math.max(0, workout.durationMin) / 60;
  const net = (MET[workout.kind] - 1) * weightKg * hours;
  return Math.max(0, net);
}

/** A planned session this close to a recorded one is the same session. */
export const PLANNED_MATCH_MIN = 90;

/**
 * Drops planned sessions that Apple Health also recorded, so one workout is never
 * counted twice. Planned sessions with no recorded match are kept.
 */
export function effectiveWorkouts<T extends { source: string; start: Date; durationMin: number }>(workouts: T[]): T[] {
  const recorded = workouts.filter((w) => w.source === 'HEALTHKIT');
  if (recorded.length === 0) return workouts;
  const slack = PLANNED_MATCH_MIN * 60_000;
  return workouts.filter((w) => {
    if (w.source !== 'PLANNED') return true;
    const start = w.start.getTime();
    const end = start + w.durationMin * 60_000;
    return !recorded.some((r) => {
      const rStart = r.start.getTime();
      const rEnd = rStart + r.durationMin * 60_000;
      return rStart < end + slack && start < rEnd + slack;
    });
  });
}

export function trainingBump(workouts: TrainingWorkout[], weightKg: number): number {
  const raw = effectiveWorkouts(workouts).reduce((sum, w) => sum + sessionKcal(w, weightKg), 0);
  const rounded = Math.round(raw / TRAINING_ROUND) * TRAINING_ROUND;
  return Math.min(TRAINING_BUMP_CAP, Math.max(0, rounded));
}

export function applyTrainingTarget(baseKcal: number, bump: number, addCalories: boolean): number {
  if (!addCalories || bump <= 0) return baseKcal;
  return Math.max(MIN_DAILY_KCAL, baseKcal + bump);
}

export function needsRefuel(input: {
  workoutEndedAt: Date;
  now: Date;
  meals: { at: Date; kcal: number }[];
  enforcementEnabled: boolean;
}): boolean {
  if (!input.enforcementEnabled) return false;
  const elapsed = (input.now.getTime() - input.workoutEndedAt.getTime()) / 60_000;
  if (elapsed < REFUEL_WINDOW_MIN || elapsed > REFUEL_WINDOW_MIN + 75) return false;
  const windowEnd = input.workoutEndedAt.getTime() + REFUEL_WINDOW_MIN * 60_000;
  return !input.meals.some(
    (m) => m.kcal >= REFUEL_MIN_KCAL && m.at.getTime() >= input.workoutEndedAt.getTime() && m.at.getTime() <= windowEnd,
  );
}

export function needsPreWorkoutNudge(input: {
  plannedStart: Date;
  now: Date;
  meals: { at: Date }[];
  nudgeMin: number | null;
  enforcementEnabled: boolean;
}): boolean {
  if (!input.enforcementEnabled || input.nudgeMin == null) return false;
  const until = (input.plannedStart.getTime() - input.now.getTime()) / 60_000;
  if (until > input.nudgeMin + 10 || until < input.nudgeMin - 10) return false;
  const lookback = input.now.getTime() - PRE_WORKOUT_LOOKBACK_MIN * 60_000;
  return !input.meals.some((m) => m.at.getTime() >= lookback);
}
