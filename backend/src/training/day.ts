import type { PrismaClient, Workout } from '@prisma/client';
import {
  applyTrainingTarget,
  effectiveWorkouts,
  trainingBump,
  type TrainingWorkout,
} from '../engine/training.js';
import { msSinceLocalMidnight, startOfLocalDay } from '../engine/time.js';

export function asTrainingWorkout(row: Pick<Workout, 'source' | 'kind' | 'start' | 'durationMin' | 'activeKcal'>): TrainingWorkout {
  return {
    source: row.source,
    kind: row.kind,
    start: row.start,
    durationMin: row.durationMin,
    activeKcal: row.activeKcal,
  };
}

export async function trainingForLocalDay(
  prisma: PrismaClient,
  input: {
    userId: string;
    now: Date;
    timezone: string;
    weightKg: number;
    baseKcal: number;
    addCalories: boolean;
  },
): Promise<{ bump: number; targetKcal: number; workouts: Workout[] }> {
  const dayStart = startOfLocalDay(input.now, input.timezone);
  const dayEnd = new Date(dayStart.getTime() + 86_400_000);
  const workouts = await prisma.workout.findMany({
    where: { userId: input.userId, start: { gte: dayStart, lt: dayEnd } },
    orderBy: { start: 'asc' },
  });
  const bump = trainingBump(workouts.map(asTrainingWorkout), input.weightKg);
  return {
    bump,
    targetKcal: applyTrainingTarget(input.baseKcal, bump, input.addCalories),
    workouts: effectiveWorkouts(workouts),
  };
}

export function workoutHomeRows(
  workouts: Workout[],
  timezone: string,
  dayStart: Date,
): { id: string; kind: string; source: string; startMin: number; durationMin: number; activeKcal: number | null }[] {
  return workouts.map((w) => ({
    id: w.id,
    kind: w.kind,
    source: w.source,
    startMin: Math.floor(msSinceLocalMidnight(w.start, timezone) / 60_000),
    durationMin: w.durationMin,
    activeKcal: w.activeKcal,
  }));
}
