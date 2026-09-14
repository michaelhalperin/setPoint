import { describe, expect, it } from 'vitest';
import {
  SCORE_CONFIG,
  SCORING_VERSION,
  computeBehaviorScore,
  expectedGapHours,
  type BehaviorScoreInput,
} from './behaviorScore.js';

const TARGET = 2400;

// Lunch just came due (13:45, lunch at 13:00), breakfast of 500 kcal at 08:00.
const lunchDue = (over: Partial<BehaviorScoreInput> = {}): BehaviorScoreInput => ({
  slot: 'lunch',
  overdueMin: 0,
  hoursSinceMeal: 5.75,
  expectedGapHours: 5,
  consumedKcal: 500,
  targetKcal: TARGET,
  slotCheckIns: [],
  wearable: null,
  wearableEnabled: false,
  ...over,
});

const dismissed = (n: number) => Array.from({ length: n }, () => ({ status: 'EXPIRED', feedbackPositive: false }));
const answered = (n: number) => Array.from({ length: n }, () => ({ status: 'LOGGED', feedbackPositive: null }));

describe('computeBehaviorScore', () => {
  it('fires as soon as a meal is due when the day is clearly behind', () => {
    const r = computeBehaviorScore(lunchDue());
    expect(r.version).toBe(SCORING_VERSION);
    expect(r.components.behind).toBe(1);
    expect(r.shouldFire).toBe(true);
  });

  it('holds a due meal when the day is already on pace', () => {
    const r = computeBehaviorScore(lunchDue({ consumedKcal: 1500 }));
    expect(r.components.behind).toBeLessThan(0.3);
    expect(r.shouldFire).toBe(false);
  });

  it('stops holding once the meal has run long enough past due', () => {
    const later = computeBehaviorScore(
      lunchDue({ consumedKcal: 1500, overdueMin: SCORE_CONFIG.overdueFullMin, hoursSinceMeal: 7.25 }),
    );
    expect(later.components.overdue).toBe(1);
    expect(later.shouldFire).toBe(true);
  });

  it('holds a meal the user keeps dismissing, then still fires if they fall far behind', () => {
    const history = dismissed(6);
    expect(computeBehaviorScore(lunchDue({ slotCheckIns: history })).shouldFire).toBe(false);
    const long = computeBehaviorScore(
      lunchDue({ slotCheckIns: history, overdueMin: SCORE_CONFIG.overdueFullMin, hoursSinceMeal: 7.25 }),
    );
    expect(long.components.slotDismissRate).toBe(1);
    expect(long.shouldFire).toBe(true);
  });

  it('never fires a meal that is always dismissed while the day is on pace', () => {
    const r = computeBehaviorScore(
      lunchDue({
        consumedKcal: 1700,
        slotCheckIns: dismissed(10),
        overdueMin: 240,
        hoursSinceMeal: 9,
      }),
    );
    expect(r.shouldFire).toBe(false);
  });

  it('only counts negative answers as dismissals', () => {
    const r = computeBehaviorScore(lunchDue({ slotCheckIns: [...dismissed(2), ...answered(8)] }));
    expect(r.components.slotDismissRate).toBe(0.2);
  });

  it('does not let a wearable fire a meal that behavior holds', () => {
    const held = lunchDue({ consumedKcal: 1500, slotCheckIns: dismissed(4) });
    const r = computeBehaviorScore({
      ...held,
      wearableEnabled: true,
      wearable: { hrvDeviation: -10, rhrDeviation: 10 },
    });
    expect(r.wearableUsed).toBe(true);
    expect(r.wearableModifier).toBe(SCORE_CONFIG.maxWearableBoost);
    expect(r.shouldFire).toBe(false);
  });

  it('is identical to Basic when the wearable is stale or switched off', () => {
    const off = computeBehaviorScore(lunchDue({ wearableEnabled: false, wearable: { hrvDeviation: -2, rhrDeviation: 2 } }));
    const missing = computeBehaviorScore(lunchDue({ wearableEnabled: true, wearable: null }));
    expect(off.score).toBe(missing.score);
    expect(off.wearableModifier).toBe(0);
  });

  it('keeps the inputs behind every component for audit', () => {
    const r = computeBehaviorScore(lunchDue({ consumedKcal: 1200 }));
    expect(r.components).toMatchObject({ consumedShare: 0.5, expectedShare: 0.667 });
  });
});

describe('expectedGapHours', () => {
  const times = { breakfastMin: 480, lunchMin: 780, dinnerMin: 1140 };
  it('uses the gap between usual meal times, and the overnight gap for breakfast', () => {
    expect(expectedGapHours('lunch', times)).toBe(5);
    expect(expectedGapHours('dinner', times)).toBe(6);
    expect(expectedGapHours('breakfast', times)).toBe(13);
  });
});
