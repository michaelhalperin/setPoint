import type { Goal } from '../engine/types.js';

export type WeightProgressInput = {
  goal: Goal;
  startWeightKg: number | null;
  targetWeightKg: number | null;
  currentWeightKg: number | null;
  paceKgPerWeek: number;
  goalStartedAt: Date | null;
  now?: Date;
};

export type PaceStatus = 'ahead' | 'on_pace' | 'behind' | 'reached' | 'unknown';

export type WeightProgress = {
  goal: Goal;
  startWeightKg: number;
  targetWeightKg: number;
  currentWeightKg: number;
  /** kg moved in the goal's direction so far, clamped to [0, total]. */
  changedKg: number;
  /** kg still to go, clamped to [0, total]. */
  remainingKg: number;
  totalKg: number;
  fractionComplete: number; // 0–1
  status: PaceStatus;
  /** Weeks left at the planned pace; null once reached or if pace is 0. */
  etaWeeks: number | null;
  reached: boolean;
};

const MS_PER_WEEK = 7 * 24 * 3_600_000;
const REACHED_EPSILON_KG = 0.2;
const round1 = (n: number): number => Math.round(n * 10) / 10;

/**
 * Goal progress from the start weight, the target, and the latest measurement
 * (M16). Returns null when there's nothing to track — MAINTAIN, no target, or
 * missing data — so callers can treat "has a weight goal" as `!= null`.
 */
export function computeWeightProgress(input: WeightProgressInput): WeightProgress | null {
  if (input.goal === 'MAINTAIN') return null;
  const { startWeightKg, targetWeightKg, currentWeightKg } = input;
  if (startWeightKg == null || targetWeightKg == null || currentWeightKg == null) return null;

  const totalKg = Math.abs(targetWeightKg - startWeightKg);
  if (totalKg < REACHED_EPSILON_KG) return null;

  const dir = input.goal === 'BULK' ? 1 : -1;
  const rawChanged = (currentWeightKg - startWeightKg) * dir;
  const changedKg = clamp(rawChanged, 0, totalKg);
  const remainingKg = round1(Math.max(0, totalKg - changedKg));
  const fractionComplete = clamp(changedKg / totalKg, 0, 1);

  // Past the target (in the goal direction) counts as reached.
  const reached = (currentWeightKg - targetWeightKg) * dir >= -REACHED_EPSILON_KG;

  const pace = Math.abs(input.paceKgPerWeek);
  let status: PaceStatus = 'unknown';
  if (reached) {
    status = 'reached';
  } else if (input.goalStartedAt) {
    const weeksElapsed = Math.max(0, (nowOf(input) - input.goalStartedAt.getTime()) / MS_PER_WEEK);
    const expectedChanged = pace * weeksElapsed;
    const drift = rawChanged - expectedChanged; // + = ahead of plan
    const band = Math.max(0.5, pace); // one week's slack, at least 0.5 kg
    status = drift > band ? 'ahead' : drift < -band ? 'behind' : 'on_pace';
  }

  const etaWeeks = reached || pace === 0 ? null : Math.ceil(remainingKg / pace);

  return {
    goal: input.goal,
    startWeightKg: round1(startWeightKg),
    targetWeightKg: round1(targetWeightKg),
    currentWeightKg: round1(currentWeightKg),
    changedKg: round1(changedKg),
    remainingKg,
    totalKg: round1(totalKg),
    fractionComplete: Math.round(fractionComplete * 100) / 100,
    status,
    etaWeeks,
    reached,
  };
}

function clamp(n: number, lo: number, hi: number): number {
  return Math.min(hi, Math.max(lo, n));
}

function nowOf(input: WeightProgressInput): number {
  return (input.now ?? new Date()).getTime();
}
