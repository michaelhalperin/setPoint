import { describe, expect, it } from 'vitest';
import { SOLVER_CONFIG } from './config.js';
import { computePrescriptionTarget } from './targets.js';

describe('computePrescriptionTarget', () => {
  it('clamps a large remaining gap down to a single meal', () => {
    const t = computePrescriptionTarget({
      dailyKcalTarget: 2800,
      consumedKcal: 600,
      dailyProteinTargetG: null,
      consumedProteinG: 0,
    });
    expect(t.targetKcal).toBe(SOLVER_CONFIG.maxMealKcal);
    expect(t.targetProteinG).toBeNull();
  });

  it('clamps a small remaining gap up to a snack', () => {
    const t = computePrescriptionTarget({
      dailyKcalTarget: 2000,
      consumedKcal: 1950,
      dailyProteinTargetG: null,
      consumedProteinG: 0,
    });
    expect(t.targetKcal).toBe(SOLVER_CONFIG.minMealKcal);
  });

  it('passes a mid-range gap straight through', () => {
    const t = computePrescriptionTarget({
      dailyKcalTarget: 2000,
      consumedKcal: 1500,
      dailyProteinTargetG: 150,
      consumedProteinG: 110,
    });
    expect(t.targetKcal).toBe(500);
    expect(t.targetProteinG).toBe(40);
  });

  it('caps the protein ask at the per-meal ceiling', () => {
    const t = computePrescriptionTarget({
      dailyKcalTarget: 2000,
      consumedKcal: 1500,
      dailyProteinTargetG: 200,
      consumedProteinG: 0,
    });
    expect(t.targetProteinG).toBe(SOLVER_CONFIG.maxProteinPerMeal);
  });
});
