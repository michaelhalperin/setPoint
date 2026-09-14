import { describe, expect, it } from 'vitest';
import { ADAPT_CONFIG, suggestTargetAdaptation } from './adapt.js';

const day = (n: number) => new Date(`2026-08-0${n}T08:00:00Z`);
const later = (iso: string) => new Date(iso);

describe('suggestTargetAdaptation', () => {
  it('returns null without enough weigh-ins', () => {
    expect(
      suggestTargetAdaptation({
        goal: 'BULK',
        currentKcal: 3000,
        paceKgPerWeek: 0.25,
        samples: [
          { measuredAt: later('2026-08-01T08:00:00Z'), weightKg: 74 },
          { measuredAt: later('2026-08-08T08:00:00Z'), weightKg: 74.1 },
        ],
      }),
    ).toBeNull();
  });

  it('suggests a bounded surplus when a bulk is stalling', () => {
    const r = suggestTargetAdaptation({
      goal: 'BULK',
      currentKcal: 3000,
      paceKgPerWeek: 0.4,
      now: later('2026-08-22T08:00:00Z'),
      samples: [
        { measuredAt: later('2026-08-01T08:00:00Z'), weightKg: 74 },
        { measuredAt: later('2026-08-08T08:00:00Z'), weightKg: 74.05 },
        { measuredAt: later('2026-08-15T08:00:00Z'), weightKg: 74.08 },
        { measuredAt: later('2026-08-22T08:00:00Z'), weightKg: 74.1 },
      ],
    });
    expect(r).not.toBeNull();
    expect(r!.proposedKcal - r!.previousKcal).toBeGreaterThanOrEqual(ADAPT_CONFIG.minKcalStep);
    expect(r!.proposedKcal - r!.previousKcal).toBeLessThanOrEqual(ADAPT_CONFIG.maxKcalStep);
    expect(r!.reason).toMatch(/slower than planned/i);
    expect(r!.reason).not.toMatch(/kg/);
  });

  it('never auto-applies — it only returns a suggestion', () => {
    const r = suggestTargetAdaptation({
      goal: 'DIET',
      currentKcal: 2000,
      paceKgPerWeek: 0.4,
      now: later('2026-08-22T08:00:00Z'),
      samples: [
        { measuredAt: later('2026-08-01T08:00:00Z'), weightKg: 82 },
        { measuredAt: later('2026-08-08T08:00:00Z'), weightKg: 80.8 },
        { measuredAt: later('2026-08-15T08:00:00Z'), weightKg: 79.5 },
        { measuredAt: later('2026-08-22T08:00:00Z'), weightKg: 78.2 },
      ],
    });
    expect(r).not.toBeNull();
    expect(r!.proposedKcal).toBeGreaterThan(2000);
    expect(Math.abs(r!.proposedKcal - 2000)).toBeLessThanOrEqual(ADAPT_CONFIG.maxKcalStep);
  });

  it('does not suggest from a MAINTAIN goal', () => {
    expect(
      suggestTargetAdaptation({
        goal: 'MAINTAIN',
        currentKcal: 2500,
        paceKgPerWeek: 0,
        samples: [
          { measuredAt: day(1), weightKg: 75 },
          { measuredAt: later('2026-08-08T08:00:00Z'), weightKg: 75 },
          { measuredAt: later('2026-08-15T08:00:00Z'), weightKg: 75 },
          { measuredAt: later('2026-08-22T08:00:00Z'), weightKg: 75 },
        ],
      }),
    ).toBeNull();
  });
});

describe('suggestTargetAdaptation — cadence', () => {
  const stalling = [
    { measuredAt: new Date('2026-08-01T08:00:00Z'), weightKg: 74 },
    { measuredAt: new Date('2026-08-08T08:00:00Z'), weightKg: 74.05 },
    { measuredAt: new Date('2026-08-15T08:00:00Z'), weightKg: 74.08 },
    { measuredAt: new Date('2026-08-22T08:00:00Z'), weightKg: 74.1 },
  ];
  const base = { goal: 'BULK' as const, currentKcal: 3000, paceKgPerWeek: 0.4, samples: stalling };

  it('stays quiet for a week after the last decision', () => {
    const now = new Date('2026-08-22T09:00:00Z');
    expect(suggestTargetAdaptation({ ...base, now, lastDecisionAt: new Date('2026-08-18T08:00:00Z') })).toBeNull();
    expect(suggestTargetAdaptation({ ...base, now, lastDecisionAt: new Date('2026-08-14T08:00:00Z') })).not.toBeNull();
  });

  it('ignores weigh-ins older than the window', () => {
    // Six weeks later, only the last sample is inside the 42-day window.
    expect(suggestTargetAdaptation({ ...base, now: new Date('2026-10-02T08:00:00Z') })).toBeNull();
  });

  it('never proposes below the daily floor', () => {
    const r = suggestTargetAdaptation({
      goal: 'DIET',
      currentKcal: 1250,
      paceKgPerWeek: 0.5,
      now: new Date('2026-08-22T09:00:00Z'),
      samples: stalling.map((s) => ({ ...s, weightKg: 80 })),
    });
    expect(r?.proposedKcal ?? 1250).toBeGreaterThanOrEqual(1200);
  });
});
