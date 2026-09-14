import { describe, expect, it } from 'vitest';
import {
  SCORE_CONFIG,
  SCORING_VERSION,
  computeBehaviorScore,
  expectedGapHours,
  type BehaviorScoreInput,
} from './behaviorScore.js';

const base = (over: Partial<BehaviorScoreInput> = {}): BehaviorScoreInput => ({
  overdueMin: 50,
  hoursSinceMeal: 5,
  expectedGapHours: 5,
  consumedKcal: 600,
  targetKcal: 2200,
  recentCheckIns: [],
  wearable: null,
  wearableEnabled: false,
  ...over,
});

describe('computeBehaviorScore', () => {
  it('fires for a clearly overdue, under-target slot with no history', () => {
    const r = computeBehaviorScore(base());
    expect(r.version).toBe(SCORING_VERSION);
    expect(r.wearableUsed).toBe(false);
    expect(r.wearableModifier).toBe(0);
    expect(r.shouldFire).toBe(true);
    expect(r.score).toBeGreaterThanOrEqual(SCORE_CONFIG.threshold);
  });

  it('does not let a wearable independently fire when behavior is quiet', () => {
    const quiet = computeBehaviorScore(
      base({
        overdueMin: 0,
        hoursSinceMeal: 0.5,
        expectedGapHours: 5,
        consumedKcal: 2200,
        targetKcal: 2200,
        wearableEnabled: true,
        wearable: { hrvDeviation: -3, rhrDeviation: 3 },
      }),
    );
    expect(quiet.wearableUsed).toBe(true);
    expect(quiet.wearableModifier).toBeGreaterThan(0);
    expect(quiet.wearableModifier).toBeLessThanOrEqual(SCORE_CONFIG.maxWearableBoost);
    expect(quiet.shouldFire).toBe(false);
  });

  it('is identical to Basic when the wearable is stale or the kill switch is off', () => {
    const off = computeBehaviorScore(
      base({ wearableEnabled: false, wearable: { hrvDeviation: -2, rhrDeviation: 2 } }),
    );
    const missing = computeBehaviorScore(base({ wearableEnabled: true, wearable: null }));
    expect(off.score).toBe(missing.score);
    expect(off.wearableModifier).toBe(0);
    expect(missing.wearableModifier).toBe(0);
  });

  it('caps the wearable boost', () => {
    const r = computeBehaviorScore(
      base({
        wearableEnabled: true,
        wearable: { hrvDeviation: -10, rhrDeviation: 10 },
      }),
    );
    expect(r.wearableModifier).toBe(SCORE_CONFIG.maxWearableBoost);
  });

  it('lowers the score when the user often dismisses as already-ate', () => {
    const honest = computeBehaviorScore(base());
    const dismissive = computeBehaviorScore(
      base({
        recentCheckIns: Array.from({ length: 8 }, () => ({
          status: 'EXPIRED',
          feedbackPositive: false,
          deferCount: 0,
        })),
      }),
    );
    expect(dismissive.score).toBeLessThan(honest.score);
    expect(dismissive.components.dismissRate).toBe(1);
  });

  it('stores every component for audit', () => {
    const r = computeBehaviorScore(base({ overdueMin: 90, consumedKcal: 0, targetKcal: 2000 }));
    expect(r.components.overdue).toBe(1);
    expect(r.components.coverage).toBe(1);
    expect(r.behaviorScore).toBeGreaterThan(0);
  });
});

describe('expectedGapHours', () => {
  const times = { breakfastMin: 480, lunchMin: 780, dinnerMin: 1140 };
  it('uses the gap between usual meal times', () => {
    expect(expectedGapHours('lunch', times)).toBe(5);
    expect(expectedGapHours('dinner', times)).toBe(6);
    expect(expectedGapHours('breakfast', times)).toBe(8);
  });
});
