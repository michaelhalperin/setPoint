import { KCAL_PER_KG } from '../onboarding/targets.js';

export const EXPENDITURE_VERSION = 'expenditure.v1';
export const EXPENDITURE_WINDOW_DAYS = 56;
export const MIN_LOGGED_DAYS = 28;
export const MIN_LOGGED_RATIO = 0.8;
export const MIN_WEIGH_INS = 6;

export type DailyIntake = { date: string; kcal: number };
export type WeighIn = { at: Date; kg: number };

export type ExpenditureEstimate = {
  version: typeof EXPENDITURE_VERSION;
  ready: boolean;
  reason: 'not_enough_days' | 'not_enough_logs' | 'not_enough_weighins' | null;
  burnKcal: number | null;
  rangeLow: number | null;
  rangeHigh: number | null;
  avgIntakeKcal: number | null;
  slopeKgPerDay: number | null;
  loggedDays: number;
  windowDays: number;
  weighIns: number;
};

export function estimateExpenditure(input: {
  days: DailyIntake[];
  weighIns: WeighIn[];
  windowDays?: number;
}): ExpenditureEstimate {
  const windowDays = input.windowDays ?? EXPENDITURE_WINDOW_DAYS;
  const days = [...input.days].sort((a, b) => a.date.localeCompare(b.date));
  const loggedDays = days.filter((d) => d.kcal > 0).length;
  const weighIns = [...input.weighIns].sort((a, b) => a.at.getTime() - b.at.getTime());

  const base = {
    version: EXPENDITURE_VERSION,
    loggedDays,
    windowDays,
    weighIns: weighIns.length,
  } as const;

  if (days.length < MIN_LOGGED_DAYS && loggedDays < MIN_LOGGED_DAYS) {
    return empty(base, 'not_enough_days');
  }
  if (loggedDays < MIN_LOGGED_DAYS) {
    return empty(base, 'not_enough_days');
  }
  if (loggedDays / windowDays < MIN_LOGGED_RATIO) {
    return empty(base, 'not_enough_logs');
  }
  if (weighIns.length < MIN_WEIGH_INS) {
    return empty(base, 'not_enough_weighins');
  }

  const avgIntakeKcal = days.reduce((sum, d) => sum + d.kcal, 0) / days.length;
  const slope = linearKgPerDay(weighIns);
  const burn = Math.max(0, avgIntakeKcal - slope * KCAL_PER_KG);
  const half = rangeHalfKcal({ days, weighIns, slope, avgIntakeKcal });
  const burnKcal = round10(burn);

  return {
    ...base,
    ready: true,
    reason: null,
    burnKcal,
    rangeLow: round10(Math.max(0, burn - half)),
    rangeHigh: round10(burn + half),
    avgIntakeKcal: round10(avgIntakeKcal),
    slopeKgPerDay: Math.round(slope * 10_000) / 10_000,
  };
}

export function weeklyIntakeBars(
  days: DailyIntake[],
  burn: { burnKcal: number; rangeLow: number; rangeHigh: number } | null,
): { weekStart: string; intakeKcal: number; burnKcal: number | null; burnLow: number | null; burnHigh: number | null }[] {
  const sorted = [...days].sort((a, b) => a.date.localeCompare(b.date));
  const weeks: { weekStart: string; intakeKcal: number; burnKcal: number | null; burnLow: number | null; burnHigh: number | null }[] = [];
  for (let i = 0; i < sorted.length; i += 7) {
    const slice = sorted.slice(i, i + 7);
    if (slice.length === 0) continue;
    const avg = slice.reduce((sum, d) => sum + d.kcal, 0) / slice.length;
    weeks.push({
      weekStart: slice[0]!.date,
      intakeKcal: round10(avg),
      burnKcal: burn?.burnKcal ?? null,
      burnLow: burn?.rangeLow ?? null,
      burnHigh: burn?.rangeHigh ?? null,
    });
  }
  return weeks;
}

function empty(
  base: { version: typeof EXPENDITURE_VERSION; loggedDays: number; windowDays: number; weighIns: number },
  reason: ExpenditureEstimate['reason'],
): ExpenditureEstimate {
  return {
    ...base,
    ready: false,
    reason,
    burnKcal: null,
    rangeLow: null,
    rangeHigh: null,
    avgIntakeKcal: null,
    slopeKgPerDay: null,
  };
}

export function linearKgPerDay(samples: WeighIn[]): number {
  if (samples.length < 2) return 0;
  const t0 = samples[0]!.at.getTime();
  const xs = samples.map((s) => (s.at.getTime() - t0) / 86_400_000);
  const ys = samples.map((s) => s.kg);
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

function rangeHalfKcal(input: {
  days: DailyIntake[];
  weighIns: WeighIn[];
  slope: number;
  avgIntakeKcal: number;
}): number {
  const n = input.days.length;
  const intakeVar =
    input.days.reduce((sum, d) => sum + (d.kcal - input.avgIntakeKcal) ** 2, 0) / Math.max(1, n - 1);
  const seIntake = Math.sqrt(intakeVar / n);

  const t0 = input.weighIns[0]!.at.getTime();
  const xs = input.weighIns.map((s) => (s.at.getTime() - t0) / 86_400_000);
  const meanX = xs.reduce((a, b) => a + b, 0) / xs.length;
  const ssx = xs.reduce((sum, x) => sum + (x - meanX) ** 2, 0);
  const residuals = input.weighIns.map((s, i) => {
    const predicted = input.weighIns[0]!.kg + input.slope * xs[i]!;
    return s.kg - predicted;
  });
  const sse = residuals.reduce((sum, r) => sum + r ** 2, 0);
  const seSlope = ssx <= 0 ? 0 : Math.sqrt(sse / Math.max(1, residuals.length - 2) / ssx);
  const seBurn = Math.sqrt(seIntake ** 2 + (seSlope * KCAL_PER_KG) ** 2);
  return Math.max(50, 1.96 * seBurn);
}

function round10(n: number): number {
  return Math.round(n / 10) * 10;
}
