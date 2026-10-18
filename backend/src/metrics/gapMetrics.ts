/**
 * The outcome that matters for people who can't eat enough: did the day's gap
 * actually close? Check-in engagement is a means; this is the end.
 *
 * Pure: the route layer queries settled days and check-ins and hands them in.
 */

export const GAP_METRICS_CONFIG = {
  /** A day counts as closed at this share of its target. */
  closedShare: 0.95,
} as const;

export type SettledDay = { kcalConsumed: number; kcalTarget: number };
export type KindRecord = { kind: string; status: string };

export type GapMetrics = {
  days: {
    total: number;
    closed: number;
    /** Share of settled days that reached the closed share of target — the headline number. */
    gapClosedRate: number;
    /** Average shortfall on the days that didn't close. */
    avgShortfallKcal: number | null;
  };
  /** How each kind of check-in ended, e.g. TOP_UP and CLOSE versus plain MEAL. */
  byKind: Record<string, { total: number; logged: number; loggedRate: number }>;
};

const rate = (n: number, d: number): number => (d === 0 ? 0 : Math.round((n / d) * 1000) / 1000);

export function buildGapMetrics(days: SettledDay[], checkIns: KindRecord[]): GapMetrics {
  const scored = days.filter((d) => d.kcalTarget > 0);
  let closed = 0;
  let shortfall = 0;
  let shortDays = 0;
  for (const d of scored) {
    if (d.kcalConsumed >= d.kcalTarget * GAP_METRICS_CONFIG.closedShare) {
      closed += 1;
    } else {
      shortfall += d.kcalTarget - d.kcalConsumed;
      shortDays += 1;
    }
  }

  const byKind: GapMetrics['byKind'] = {};
  for (const c of checkIns) {
    const row = (byKind[c.kind] ??= { total: 0, logged: 0, loggedRate: 0 });
    row.total += 1;
    if (c.status === 'LOGGED') row.logged += 1;
  }
  for (const row of Object.values(byKind)) row.loggedRate = rate(row.logged, row.total);

  return {
    days: {
      total: scored.length,
      closed,
      gapClosedRate: rate(closed, scored.length),
      avgShortfallKcal: shortDays === 0 ? null : Math.round(shortfall / shortDays),
    },
    byKind,
  };
}
