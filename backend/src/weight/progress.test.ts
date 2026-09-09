import { describe, expect, it } from 'vitest';
import { computeWeightProgress } from './progress.js';

const START = new Date('2026-08-01T00:00:00Z');
const now = (weeks: number) => new Date(START.getTime() + weeks * 7 * 24 * 3_600_000);

describe('computeWeightProgress', () => {
  it('returns null for MAINTAIN or a missing target', () => {
    const base = {
      goal: 'MAINTAIN' as const,
      startWeightKg: 80,
      targetWeightKg: null,
      currentWeightKg: 80,
      paceKgPerWeek: 0,
      goalStartedAt: START,
    };
    expect(computeWeightProgress(base)).toBeNull();
    expect(computeWeightProgress({ ...base, goal: 'DIET', targetWeightKg: null })).toBeNull();
    expect(computeWeightProgress({ ...base, goal: 'DIET', targetWeightKg: 74, currentWeightKg: null })).toBeNull();
  });

  it('tracks a diet: kg lost, kg remaining, fraction', () => {
    const p = computeWeightProgress({
      goal: 'DIET',
      startWeightKg: 80,
      targetWeightKg: 74,
      currentWeightKg: 77,
      paceKgPerWeek: 0.5,
      goalStartedAt: START,
      now: now(6),
    });
    expect(p).not.toBeNull();
    expect(p!.changedKg).toBe(3);
    expect(p!.remainingKg).toBe(3);
    expect(p!.totalKg).toBe(6);
    expect(p!.fractionComplete).toBe(0.5);
  });

  it('flags reached and switches status when the target is hit', () => {
    const p = computeWeightProgress({
      goal: 'DIET',
      startWeightKg: 80,
      targetWeightKg: 74,
      currentWeightKg: 73.5,
      paceKgPerWeek: 0.5,
      goalStartedAt: START,
      now: now(12),
    });
    expect(p!.reached).toBe(true);
    expect(p!.status).toBe('reached');
    expect(p!.etaWeeks).toBeNull();
  });

  it('reads behind / on_pace / ahead against the planned pace', () => {
    const common = {
      goal: 'DIET' as const,
      startWeightKg: 80,
      targetWeightKg: 70,
      paceKgPerWeek: 0.5,
      goalStartedAt: START,
      now: now(8), // expected 4 kg lost by now
    };
    expect(computeWeightProgress({ ...common, currentWeightKg: 79.5 })!.status).toBe('behind');
    expect(computeWeightProgress({ ...common, currentWeightKg: 76 })!.status).toBe('on_pace');
    expect(computeWeightProgress({ ...common, currentWeightKg: 73 })!.status).toBe('ahead');
  });

  it('estimates weeks left at the planned pace', () => {
    const p = computeWeightProgress({
      goal: 'BULK',
      startWeightKg: 70,
      targetWeightKg: 76,
      currentWeightKg: 72,
      paceKgPerWeek: 0.25,
      goalStartedAt: START,
      now: now(8),
    });
    expect(p!.remainingKg).toBe(4);
    expect(p!.etaWeeks).toBe(16);
  });
});
