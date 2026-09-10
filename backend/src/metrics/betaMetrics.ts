/**
 * Beta tuning instrumentation (plan §8).
 *
 * The one number the plan says to watch is the **false-positive rate** — a
 * check-in that fired when the person had actually already eaten. We approximate
 * it two ways and report both:
 *   - explicit: the user tapped thumbs-down on the check-in.
 *   - inferred: a meal was logged with a timestamp shortly before the check-in
 *     was delivered (they had eaten, just hadn't logged it yet).
 *
 * Pure: the route layer does the Prisma queries and hands the shaped records in.
 */

export type CheckInStatusName =
  | 'PENDING'
  | 'LOGGED'
  | 'DEFERRED'
  | 'ESCALATED'
  | 'EXPIRED'
  | 'BACKED_OFF';

export type CheckInMetricRecord = {
  tier: number;
  status: CheckInStatusName;
  deferCount: number;
  feedbackPositive: boolean | null;
  firedConfidence: number | null;
  /** A meal exists with `loggedAt` inside [deliveredAt − window, deliveredAt]. */
  ateShortlyBefore: boolean;
};

export type BetaMetrics = {
  window: { from: string; to: string; falsePositiveWindowMinutes: number };
  checkIns: {
    total: number;
    byTier: Record<'1' | '2' | '3', number>;
    byStatus: Record<CheckInStatusName, number>;
    /** EXPIRED + ESCALATED — the user never engaged. */
    missRate: number;
    /** Resolved by a logged meal. */
    loggedRate: number;
    /** Deferred at least once. */
    deferRate: number;
    avgFiredConfidence: number | null;
  };
  feedback: {
    positive: number;
    negative: number;
    none: number;
    /** Share of check-ins that got a thumbs up/down. */
    responseRate: number;
    /** Of those rated, the share rated positive. */
    positiveRate: number | null;
  };
  falsePositives: {
    /** Thumbs-down. */
    explicit: number;
    explicitRate: number;
    /** Inferred: ate shortly before the check-in fired. */
    inferredAteBefore: number;
    inferredAteBeforeRate: number;
    /** Either signal — the headline number to tune against (§8). */
    combined: number;
    combinedRate: number;
  };
};

const rate = (n: number, d: number): number => (d === 0 ? 0 : Math.round((n / d) * 1000) / 1000);

export function buildBetaMetrics(
  records: CheckInMetricRecord[],
  opts: { from: Date; to: Date; falsePositiveWindowMinutes: number },
): BetaMetrics {
  const total = records.length;

  const byTier = { '1': 0, '2': 0, '3': 0 } as Record<'1' | '2' | '3', number>;
  const byStatus: Record<CheckInStatusName, number> = {
    PENDING: 0,
    LOGGED: 0,
    DEFERRED: 0,
    ESCALATED: 0,
    EXPIRED: 0,
    BACKED_OFF: 0,
  };

  let positive = 0;
  let negative = 0;
  let deferred = 0;
  let missed = 0;
  let logged = 0;
  let inferredAteBefore = 0;
  let combined = 0;
  let confidenceSum = 0;
  let confidenceN = 0;

  for (const r of records) {
    const tierKey = (r.tier <= 1 ? '1' : r.tier >= 3 ? '3' : '2') as '1' | '2' | '3';
    byTier[tierKey] += 1;
    if (r.status in byStatus) byStatus[r.status] += 1;

    if (r.feedbackPositive === true) positive += 1;
    if (r.feedbackPositive === false) negative += 1;
    if (r.deferCount > 0) deferred += 1;
    if (r.status === 'EXPIRED' || r.status === 'ESCALATED') missed += 1;
    if (r.status === 'LOGGED') logged += 1;
    if (r.ateShortlyBefore) inferredAteBefore += 1;
    if (r.feedbackPositive === false || r.ateShortlyBefore) combined += 1;

    if (r.firedConfidence !== null) {
      confidenceSum += r.firedConfidence;
      confidenceN += 1;
    }
  }

  const rated = positive + negative;

  return {
    window: {
      from: opts.from.toISOString(),
      to: opts.to.toISOString(),
      falsePositiveWindowMinutes: opts.falsePositiveWindowMinutes,
    },
    checkIns: {
      total,
      byTier,
      byStatus,
      missRate: rate(missed, total),
      loggedRate: rate(logged, total),
      deferRate: rate(deferred, total),
      avgFiredConfidence:
        confidenceN === 0 ? null : Math.round((confidenceSum / confidenceN) * 1000) / 1000,
    },
    feedback: {
      positive,
      negative,
      none: total - rated,
      responseRate: rate(rated, total),
      positiveRate: rated === 0 ? null : rate(positive, rated),
    },
    falsePositives: {
      explicit: negative,
      explicitRate: rate(negative, total),
      inferredAteBefore,
      inferredAteBeforeRate: rate(inferredAteBefore, total),
      combined,
      combinedRate: rate(combined, total),
    },
  };
}
