/**
 * One sentence for the owner: why this check-in (the notification) went out.
 * Built from stored fields — never invents a reason the engine didn't record.
 */

export type CheckInWhyInput = {
  kind: string;
  slot: string | null;
  tier: number;
  movedFromMin: number | null;
  coveredByDinner: boolean;
  hoursSinceMeal: number | null;
  overdueMin: number | null;
};

export function prettySlot(slot: string | null): string | null {
  if (!slot) return null;
  const names: Record<string, string> = {
    breakfast: 'breakfast',
    lunch: 'lunch',
    dinner: 'dinner',
    snack_am: 'the morning snack',
    snack_pm: 'the afternoon snack',
    close: 'the evening close',
    refuel: 'refuel',
    preworkout: 'pre-workout',
  };
  return names[slot] ?? slot.replace(/_/g, ' ');
}

export type AdminCheckInRow = {
  id: string;
  createdAt: Date;
  deliveredAt: Date | null;
  kind: string;
  slot: string | null;
  tier: number;
  status: string;
  deliveryStatus: string;
  message: string | null;
  movedFromMin: number | null;
  coveredByDinner: boolean;
  lastPushError: string | null;
  feedbackPositive: boolean | null;
  confidenceScore: { hoursSinceMeal: number | null; overdueMin: number | null } | null;
  user?: { id: string; email: string | null; cohort: string | null };
};

/** The fields the dashboard needs for one notification: when it went out, and why. */
export function toAdminCheckIn<T extends AdminCheckInRow>(c: T) {
  return {
    id: c.id,
    createdAt: c.createdAt,
    deliveredAt: c.deliveredAt,
    when: c.deliveredAt ?? c.createdAt,
    kind: c.kind,
    slot: c.slot,
    tier: c.tier,
    status: c.status,
    deliveryStatus: c.deliveryStatus,
    message: c.message,
    lastPushError: c.lastPushError,
    feedbackPositive: c.feedbackPositive,
    why: checkInWhy({
      kind: c.kind,
      slot: c.slot,
      tier: c.tier,
      movedFromMin: c.movedFromMin,
      coveredByDinner: c.coveredByDinner,
      hoursSinceMeal: c.confidenceScore?.hoursSinceMeal ?? null,
      overdueMin: c.confidenceScore?.overdueMin ?? null,
    }),
    ...(c.user ? { user: c.user } : {}),
  };
}

export function checkInWhy(c: CheckInWhyInput): string {
  if (c.coveredByDinner) return 'Closed — dinner covered it';
  if (c.tier >= 3) return 'Talk after consecutive missed check-ins';
  const slot = prettySlot(c.slot);
  const cap = slot ? slot[0]!.toUpperCase() + slot.slice(1) : null;

  switch (c.kind) {
    case 'TOP_UP':
      return cap ? `${cap} was too light for where the day should be` : 'A logged meal was too light for the day';
    case 'CLOSE':
      return 'Evening — still short of today’s calorie target';
    case 'HEADS_UP':
      return cap
        ? `${cap} moved earlier because of a busy calendar block`
        : 'Moved earlier because of a busy calendar block';
    case 'REFUEL':
      return 'After training — no refuel logged';
    case 'PRE_WORKOUT':
      return 'Training soon — eat something first';
    case 'MEAL':
    default: {
      const bits = [cap ? `Nothing logged for ${slot} when it was due` : 'A meal was due and nothing was logged'];
      if (c.overdueMin != null && c.overdueMin >= 1) bits.push(`${Math.round(c.overdueMin)} min overdue`);
      if (c.hoursSinceMeal != null && c.hoursSinceMeal >= 1) bits.push(`${c.hoursSinceMeal.toFixed(1)} h since last meal`);
      return bits.join(' · ');
    }
  }
}
