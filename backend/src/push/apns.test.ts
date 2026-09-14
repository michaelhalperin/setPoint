import { describe, expect, it } from 'vitest';
import { buildCheckInAlertPayload, buildLiveActivityPayload } from './apns.js';
import type { PushPayload } from './types.js';

const payload: PushPayload = {
  userId: 'u1',
  checkInId: 'ci_42',
  tier: 2,
  title: 'SetPoint',
  body: "You're well past your usual meal gap.",
};

describe('buildCheckInAlertPayload', () => {
  it('marks the alert Time Sensitive (not a critical alert — plan §2)', () => {
    const p = buildCheckInAlertPayload(payload) as { aps: Record<string, unknown> };
    expect(p.aps['interruption-level']).toBe('time-sensitive');
    expect(p.aps).not.toHaveProperty('critical');
  });

  it('carries the deep link into the prescription view', () => {
    const p = buildCheckInAlertPayload(payload) as Record<string, unknown>;
    expect(p.deepLink).toBe('setpoint://check-in/ci_42');
    expect(p.checkInId).toBe('ci_42');
    expect(p.tier).toBe(2);
  });

  it('uses the provided title and body', () => {
    const p = buildCheckInAlertPayload(payload) as { aps: { alert: { title: string; body: string } } };
    expect(p.aps.alert).toEqual({ title: 'SetPoint', body: payload.body });
  });

  it('offers the notification actions for a meal check-in, not for the tier-3 talk', () => {
    const meal = buildCheckInAlertPayload({ ...payload, prescriptionId: 'rx_7' }) as { aps: Record<string, unknown>; prescriptionId: string };
    expect(meal.aps.category).toBe('CHECK_IN');
    expect(meal.prescriptionId).toBe('rx_7');

    const talk = buildCheckInAlertPayload({ ...payload, tier: 3 }) as { aps: Record<string, unknown> };
    expect(talk.aps).not.toHaveProperty('category');
  });
});

describe('buildLiveActivityPayload', () => {
  const state = { title: 'Time to eat', detail: '2 eggs + toast', deepLink: 'setpoint://check-in/ci_1' };

  it('a start push carries attributes + an alert', () => {
    const p = buildLiveActivityPayload('start', state, { checkInId: 'ci_1' }) as { aps: Record<string, unknown> };
    expect(p.aps.event).toBe('start');
    expect(p.aps['attributes-type']).toBe('CheckInActivityAttributes');
    expect(p.aps.attributes).toEqual({ checkInId: 'ci_1' });
    expect(p.aps).toHaveProperty('alert');
    expect(p.aps['content-state']).toEqual(state);
  });

  it('an update push has no attributes or alert', () => {
    const p = buildLiveActivityPayload('update', state) as { aps: Record<string, unknown> };
    expect(p.aps.event).toBe('update');
    expect(p.aps).not.toHaveProperty('attributes');
    expect(p.aps).not.toHaveProperty('alert');
  });
});
