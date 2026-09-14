import type { Goal } from '../engine/types.js';
import { MIN_DAILY_KCAL } from '../onboarding/targets.js';

export const ADAPT_VERSION = 'adapt.v1';

export const ADAPT_CONFIG = {
  minWeighIns: 4,
  minSpanDays: 14,
  minKcalStep: 50,
  maxKcalStep: 100,
  /** Only weigh-ins this recent count toward the trend. */
  windowDays: 42,
  /** One review per week: nothing is suggested this soon after a decision. */
  cooldownDays: 7,
} as const;

export type WeightSample = { measuredAt: Date; weightKg: number };

export type AdaptInput = {
  goal: Goal;
  currentKcal: number;
  paceKgPerWeek: number;
  samples: WeightSample[];
  /** When the user last accepted, dismissed, or undid a review. */
  lastDecisionAt?: Date | null;
  now?: Date;
};

export type AdaptSuggestion = {
  formulaVersion: typeof ADAPT_VERSION;
  previousKcal: number;
  proposedKcal: number;
  deltaKcal: number;
  reason: string;
  windowStart: Date;
  windowEnd: Date;
  weighInCount: number;
  trendKgPerWeek: number;
};

/**
 * Bounded, trend-based calorie suggestion. Never auto-applies. Returns null
 * when there isn't enough quality data.
 */
export function suggestTargetAdaptation(input: AdaptInput): AdaptSuggestion | null {
  if (input.goal === 'MAINTAIN') return null;
  const now = input.now ?? new Date();
  if (input.lastDecisionAt && now.getTime() - input.lastDecisionAt.getTime() < ADAPT_CONFIG.cooldownDays * 86_400_000) {
    return null;
  }
  const windowStart = now.getTime() - ADAPT_CONFIG.windowDays * 86_400_000;
  const samples = input.samples
    .filter((s) => s.measuredAt.getTime() >= windowStart && s.measuredAt.getTime() <= now.getTime())
    .sort((a, b) => a.measuredAt.getTime() - b.measuredAt.getTime());
  if (samples.length < ADAPT_CONFIG.minWeighIns) return null;

  const first = samples[0]!;
  const last = samples[samples.length - 1]!;
  const spanDays = (last.measuredAt.getTime() - first.measuredAt.getTime()) / 86_400_000;
  if (spanDays < ADAPT_CONFIG.minSpanDays) return null;

  const trendKgPerWeek = linearKgPerWeek(samples);
  const expected = input.goal === 'BULK' ? Math.abs(input.paceKgPerWeek) : -Math.abs(input.paceKgPerWeek);
  const drift = trendKgPerWeek - expected;

  let delta = 0;
  let reason = '';
  if (input.goal === 'BULK') {
    if (drift < -0.1) {
      delta = clampStep(Math.round((-drift * 7700) / 7));
      reason = `Weight rose ${fmt(trendKgPerWeek)} kg/week over ${Math.round(spanDays)} days, slower than the planned ${fmt(expected)} kg/week.`;
    } else if (drift > 0.25) {
      delta = -clampStep(Math.round((drift * 7700) / 7));
      reason = `Weight rose ${fmt(trendKgPerWeek)} kg/week — faster than planned. A small cut keeps the pace honest.`;
    }
  } else {
    // DIET: trend should be negative. Faster loss than planned → ease the cut.
    if (drift < -0.15) {
      delta = clampStep(Math.round((-drift * 7700) / 7));
      reason = `Weight fell ${fmt(-trendKgPerWeek)} kg/week — faster than planned. Easing the target is safer.`;
    } else if (drift > 0.1) {
      delta = -clampStep(Math.round((drift * 7700) / 7));
      reason = `Weight moved ${fmt(trendKgPerWeek)} kg/week over ${Math.round(spanDays)} days, slower than the planned ${fmt(expected)} kg/week.`;
    }
  }

  if (delta === 0) return null;
  const proposedKcal = Math.max(MIN_DAILY_KCAL, input.currentKcal + delta);
  if (proposedKcal === input.currentKcal) return null;

  return {
    formulaVersion: ADAPT_VERSION,
    previousKcal: input.currentKcal,
    proposedKcal,
    deltaKcal: proposedKcal - input.currentKcal,
    reason,
    windowStart: first.measuredAt,
    windowEnd: now,
    weighInCount: samples.length,
    trendKgPerWeek: Math.round(trendKgPerWeek * 100) / 100,
  };
}

function linearKgPerWeek(samples: WeightSample[]): number {
  const t0 = samples[0]!.measuredAt.getTime();
  const xs = samples.map((s) => (s.measuredAt.getTime() - t0) / (7 * 86_400_000));
  const ys = samples.map((s) => s.weightKg);
  const n = xs.length;
  const meanX = xs.reduce((a, b) => a + b, 0) / n;
  const meanY = ys.reduce((a, b) => a + b, 0) / n;
  let num = 0;
  let den = 0;
  for (let i = 0; i < n; i += 1) {
    num += (xs[i]! - meanX) * (ys[i]! - meanY);
    den += (xs[i]! - meanX) ** 2;
  }
  return den === 0 ? 0 : num / den;
}

function clampStep(n: number): number {
  const mag = Math.min(ADAPT_CONFIG.maxKcalStep, Math.max(ADAPT_CONFIG.minKcalStep, Math.abs(n)));
  return n < 0 ? -mag : mag;
}

function fmt(n: number): string {
  return (Math.round(Math.abs(n) * 100) / 100).toString();
}
