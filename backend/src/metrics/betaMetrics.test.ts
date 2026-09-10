import { describe, expect, it } from 'vitest';
import { buildBetaMetrics, type CheckInMetricRecord } from './betaMetrics.js';

const rec = (over: Partial<CheckInMetricRecord> = {}): CheckInMetricRecord => ({
  tier: 2,
  status: 'LOGGED',
  deferCount: 0,
  feedbackPositive: null,
  firedConfidence: 0.8,
  ateShortlyBefore: false,
  ...over,
});

const opts = { from: new Date('2026-08-20'), to: new Date('2026-09-10'), falsePositiveWindowMinutes: 90 };

describe('buildBetaMetrics', () => {
  it('counts tiers, statuses and resolution rates', () => {
    const m = buildBetaMetrics(
      [
        rec({ tier: 1, status: 'LOGGED' }),
        rec({ tier: 2, status: 'DEFERRED', deferCount: 1 }),
        rec({ tier: 2, status: 'EXPIRED' }),
        rec({ tier: 3, status: 'ESCALATED' }),
      ],
      opts,
    );
    expect(m.checkIns.total).toBe(4);
    expect(m.checkIns.byTier).toEqual({ '1': 1, '2': 2, '3': 1 });
    expect(m.checkIns.byStatus.EXPIRED).toBe(1);
    expect(m.checkIns.missRate).toBe(0.5); // EXPIRED + ESCALATED
    expect(m.checkIns.loggedRate).toBe(0.25);
    expect(m.checkIns.deferRate).toBe(0.25);
  });

  it('separates explicit and inferred false positives and combines them', () => {
    const m = buildBetaMetrics(
      [
        rec({ feedbackPositive: false }), // explicit only
        rec({ ateShortlyBefore: true }), // inferred only
        rec({ feedbackPositive: false, ateShortlyBefore: true }), // both — counted once
        rec({ feedbackPositive: true }),
      ],
      opts,
    );
    expect(m.falsePositives.explicit).toBe(2);
    expect(m.falsePositives.inferredAteBefore).toBe(2);
    expect(m.falsePositives.combined).toBe(3);
    expect(m.falsePositives.combinedRate).toBe(0.75);
  });

  it('reports feedback response and positive rates', () => {
    const m = buildBetaMetrics(
      [
        rec({ feedbackPositive: true }),
        rec({ feedbackPositive: true }),
        rec({ feedbackPositive: false }),
        rec({ feedbackPositive: null }),
      ],
      opts,
    );
    expect(m.feedback).toMatchObject({ positive: 2, negative: 1, none: 1 });
    expect(m.feedback.responseRate).toBe(0.75);
    expect(m.feedback.positiveRate).toBe(0.667);
  });

  it('averages fired confidence, ignoring nulls', () => {
    const m = buildBetaMetrics(
      [rec({ firedConfidence: 0.7 }), rec({ firedConfidence: 0.9 }), rec({ firedConfidence: null })],
      opts,
    );
    expect(m.checkIns.avgFiredConfidence).toBe(0.8);
  });

  it('handles an empty range without dividing by zero', () => {
    const m = buildBetaMetrics([], opts);
    expect(m.checkIns.total).toBe(0);
    expect(m.checkIns.missRate).toBe(0);
    expect(m.feedback.positiveRate).toBeNull();
    expect(m.checkIns.avgFiredConfidence).toBeNull();
  });
});
