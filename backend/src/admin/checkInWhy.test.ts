import { describe, expect, it } from 'vitest';
import { checkInWhy, toAdminCheckIn } from './checkInWhy.js';

const base = {
  kind: 'MEAL',
  slot: 'lunch' as string | null,
  tier: 1,
  movedFromMin: null as number | null,
  coveredByDinner: false,
  hoursSinceMeal: null as number | null,
  overdueMin: null as number | null,
};

describe('checkInWhy', () => {
  it('says a meal slot was due and nothing was logged', () => {
    expect(checkInWhy(base)).toBe('Nothing logged for lunch when it was due');
  });

  it('adds overdue and hours since the last meal when the score recorded them', () => {
    expect(checkInWhy({ ...base, overdueMin: 42, hoursSinceMeal: 3.2 })).toBe(
      'Nothing logged for lunch when it was due · 42 min overdue · 3.2 h since last meal',
    );
  });

  it('names a light meal, the evening close, calendar, and training', () => {
    expect(checkInWhy({ ...base, kind: 'TOP_UP', slot: 'dinner' })).toBe(
      'Dinner was too light for where the day should be',
    );
    expect(checkInWhy({ ...base, kind: 'CLOSE', slot: 'close' })).toBe(
      'Evening — still short of today’s calorie target',
    );
    expect(checkInWhy({ ...base, kind: 'HEADS_UP', slot: 'lunch', movedFromMin: 780 })).toBe(
      'Lunch moved earlier because of a busy calendar block',
    );
    expect(checkInWhy({ ...base, kind: 'REFUEL', slot: 'refuel' })).toBe('After training — no refuel logged');
    expect(checkInWhy({ ...base, kind: 'PRE_WORKOUT', slot: 'preworkout' })).toBe(
      'Training soon — eat something first',
    );
  });

  it('names a tier-3 talk and dinner covering a training check-in', () => {
    expect(checkInWhy({ ...base, kind: 'MEAL', tier: 3 })).toBe('Talk after consecutive missed check-ins');
    expect(checkInWhy({ ...base, kind: 'REFUEL', coveredByDinner: true })).toBe('Closed — dinner covered it');
  });

  it('uses the push time when it exists, otherwise the moment the engine created it', () => {
    const createdAt = new Date('2026-10-21T08:00:00.000Z');
    const deliveredAt = new Date('2026-10-21T08:00:04.000Z');
    const row = {
      id: 'ci1',
      createdAt,
      deliveredAt,
      kind: 'MEAL',
      slot: 'breakfast',
      tier: 1,
      status: 'PENDING',
      deliveryStatus: 'SENT',
      message: 'Breakfast slipped. Eggs now.',
      movedFromMin: null,
      coveredByDinner: false,
      lastPushError: null,
      feedbackPositive: null,
      confidenceScore: { hoursSinceMeal: 12, overdueMin: 20 },
      user: { id: 'u1', email: 'a@b.co', group: 'pilot' },
    };
    expect(toAdminCheckIn(row)).toMatchObject({
      when: deliveredAt,
      why: 'Nothing logged for breakfast when it was due · 20 min overdue · 12.0 h since last meal',
      user: { id: 'u1', email: 'a@b.co', group: 'pilot' },
    });
    expect(toAdminCheckIn({ ...row, deliveredAt: null }).when).toEqual(createdAt);
  });
});
