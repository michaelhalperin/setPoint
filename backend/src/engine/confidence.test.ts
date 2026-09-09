import { describe, expect, it } from 'vitest';
import { CONFIDENCE_WEIGHTS } from './config.js';
import { computeConfidence, normalizeBiosignal, type ConfidenceInput } from './confidence.js';

const base: ConfidenceInput = {
  mode: 'BASIC',
  hoursSinceMeal: 1,
  expectedGapHours: 5.5,
  hoursSinceLastLog: 1,
  biosignal: null,
};

describe('normalizeBiosignal', () => {
  it('treats HRV suppression and RHR elevation as the only signal', () => {
    expect(normalizeBiosignal(-2, null, 2)).toBe(1);
    expect(normalizeBiosignal(-1, 1, 2)).toBe(0.5);
  });

  it('ignores the healthy direction (no negative evidence)', () => {
    expect(normalizeBiosignal(2, null, 2)).toBe(0);
    expect(normalizeBiosignal(1.5, -3, 2)).toBe(0);
  });

  it('clamps to 1', () => {
    expect(normalizeBiosignal(-10, 10, 2)).toBe(1);
  });
});

describe('computeConfidence — basic mode', () => {
  it('stays well below threshold right after a meal', () => {
    const r = computeConfidence(base);
    expect(r.fires).toBe(false);
    expect(r.score).toBeCloseTo(0.6 * (1 / 5.5) + 0.4 * (1 / 8), 5);
    expect(r.components.biosignalDeviation).toBeNull();
  });

  it('fires once the meal gap alone is severe enough', () => {
    // 8h since meal, expected 5h → ratio 1.6 clamped to 1.5 → 0.6*1.5 = 0.9
    const r = computeConfidence({ ...base, hoursSinceMeal: 8, expectedGapHours: 5, hoursSinceLastLog: 8 });
    expect(r.components.mealGapRatio).toBe(1.5);
    expect(r.components.loggingSilence).toBe(1);
    expect(r.score).toBe(1); // clamped
    expect(r.fires).toBe(true);
  });

  it('does not fire just below the line', () => {
    // ratio 0.6, silence 0.375 → 0.36 + 0.15 = 0.51
    const r = computeConfidence({ ...base, hoursSinceMeal: 3, expectedGapHours: 5, hoursSinceLastLog: 3 });
    expect(r.score).toBeCloseTo(0.51, 5);
    expect(r.fires).toBe(false);
  });

  it('brackets the threshold: just under does not fire, just over does', () => {
    const under = computeConfidence({ ...base, hoursSinceMeal: 5.7, expectedGapHours: 5, hoursSinceLastLog: 0 });
    const over = computeConfidence({ ...base, hoursSinceMeal: 5.9, expectedGapHours: 5, hoursSinceLastLog: 0 });
    expect(under.score).toBeLessThan(0.7);
    expect(under.fires).toBe(false);
    expect(over.score).toBeGreaterThan(0.7);
    expect(over.fires).toBe(true);
  });

  it('fires exactly when score exceeds the threshold', () => {
    for (const hoursSinceMeal of [0, 2, 4, 5, 6, 8, 12]) {
      const r = computeConfidence({ ...base, hoursSinceMeal, expectedGapHours: 5, hoursSinceLastLog: hoursSinceMeal });
      expect(r.fires).toBe(r.score > r.threshold);
    }
  });
});

describe('computeConfidence — smart mode', () => {
  it('applies the smart weights when a fresh biosignal exists', () => {
    const r = computeConfidence({
      ...base,
      mode: 'SMART',
      hoursSinceMeal: 3,
      expectedGapHours: 6, // ratio 0.5
      hoursSinceLastLog: 2, // silence 0.25
      biosignal: { hrvZ: -2, rhrZ: null }, // deviation 1
    });
    const w = CONFIDENCE_WEIGHTS.smart;
    expect(r.usedBiosignal).toBe(true);
    expect(r.components.biosignalDeviation).toBe(1);
    expect(r.score).toBeCloseTo(w.biosignal * 1 + w.mealGap * 0.5 + w.silence * 0.25, 5);
  });

  it('falls back to basic weights when no biosignal is available', () => {
    const withBio = computeConfidence({
      ...base,
      mode: 'SMART',
      biosignal: { hrvZ: -2, rhrZ: null },
      hoursSinceMeal: 4,
      expectedGapHours: 6,
      hoursSinceLastLog: 4,
    });
    const withoutBio = computeConfidence({
      ...base,
      mode: 'SMART',
      biosignal: null,
      hoursSinceMeal: 4,
      expectedGapHours: 6,
      hoursSinceLastLog: 4,
    });
    const asBasic = computeConfidence({
      ...base,
      mode: 'BASIC',
      hoursSinceMeal: 4,
      expectedGapHours: 6,
      hoursSinceLastLog: 4,
    });

    expect(withoutBio.usedBiosignal).toBe(false);
    expect(withoutBio.score).toBe(asBasic.score);
    expect(withBio.score).not.toBe(withoutBio.score);
  });
});
