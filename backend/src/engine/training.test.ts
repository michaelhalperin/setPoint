import { describe, expect, it } from 'vitest';
import {
  applyTrainingTarget,
  needsPreWorkoutNudge,
  needsRefuel,
  sessionKcal,
  trainingBump,
  TRAINING_BUMP_CAP,
} from './training.js';

const strength = {
  source: 'PLANNED' as const,
  kind: 'STRENGTH' as const,
  start: new Date('2026-09-14T15:00:00Z'),
  durationMin: 60,
  activeKcal: null,
};

describe('training.v1', () => {
  it('uses HealthKit active kcal when present', () => {
    expect(sessionKcal({ ...strength, activeKcal: 350 }, 80)).toBe(350);
  });

  it('falls back to MET × weight × hours minus resting', () => {
    // (6-1) * 80 * 1h = 400
    expect(sessionKcal(strength, 80)).toBe(400);
  });

  it('rounds to 50 and caps at 800', () => {
    expect(trainingBump([strength], 80)).toBe(400);
    const long = { ...strength, durationMin: 240, kind: 'CARDIO' as const };
    expect(trainingBump([long], 90)).toBe(TRAINING_BUMP_CAP);
  });

  it('never lowers the daily floor', () => {
    expect(applyTrainingTarget(1200, 0, true)).toBe(1200);
    expect(applyTrainingTarget(3000, 350, true)).toBe(3350);
    expect(applyTrainingTarget(3000, 350, false)).toBe(3000);
  });
});

describe('refuel', () => {
  const ended = new Date('2026-09-14T16:00:00Z');
  const now = new Date('2026-09-14T16:50:00Z');

  it('fires when nothing substantial was logged in the window', () => {
    expect(needsRefuel({ workoutEndedAt: ended, now, meals: [], enforcementEnabled: true })).toBe(true);
    expect(
      needsRefuel({
        workoutEndedAt: ended,
        now,
        meals: [{ at: new Date('2026-09-14T16:10:00Z'), kcal: 400 }],
        enforcementEnabled: true,
      }),
    ).toBe(false);
  });

  it('stays quiet when check-ins are off', () => {
    expect(needsRefuel({ workoutEndedAt: ended, now, meals: [], enforcementEnabled: false })).toBe(false);
  });
});

describe('pre-workout nudge', () => {
  const start = new Date('2026-09-14T17:00:00Z');
  const now = new Date('2026-09-14T15:30:00Z');

  it('fires 90 minutes out when nothing was logged in the last 3 hours', () => {
    expect(
      needsPreWorkoutNudge({ plannedStart: start, now, meals: [], nudgeMin: 90, enforcementEnabled: true }),
    ).toBe(true);
  });
});
