import { describe, expect, it } from 'vitest';
import { checkEligibility, type EligibilityContext } from './eligibility.js';

// A user who should be eligible: onboarded, enforcement on, no active check-in,
// midday in their timezone, quiet hours 23:00–07:00.
const ok: EligibilityContext = {
  now: new Date('2026-03-10T17:00:00Z'), // 12:00 in New York
  timezone: 'America/New_York',
  onboardingCompleted: true,
  enforcementEnabled: true,
  checkInsPaused: false,
  backedOffUntil: null,
  quietHoursStartMin: 1380,
  quietHoursEndMin: 420,
  hasActiveCheckIn: false,
};

describe('checkEligibility', () => {
  it('passes for a normal midday user', () => {
    expect(checkEligibility(ok)).toEqual({ eligible: true });
  });

  it('blocks before onboarding is complete', () => {
    expect(checkEligibility({ ...ok, onboardingCompleted: false })).toEqual({
      eligible: false,
      reason: 'onboarding_incomplete',
    });
  });

  it('blocks when enforcement is disabled by the safety screen', () => {
    expect(checkEligibility({ ...ok, enforcementEnabled: false }).eligible).toBe(false);
  });

  it('blocks while check-ins are paused', () => {
    expect(checkEligibility({ ...ok, checkInsPaused: true })).toMatchObject({ reason: 'checkins_paused' });
  });

  it('blocks during an active back-off but not after it passes', () => {
    expect(
      checkEligibility({ ...ok, backedOffUntil: new Date('2026-03-11T00:00:00Z') }),
    ).toMatchObject({ reason: 'backed_off' });
    expect(
      checkEligibility({ ...ok, backedOffUntil: new Date('2026-03-10T00:00:00Z') }).eligible,
    ).toBe(true);
  });

  it('blocks when a check-in is already active', () => {
    expect(checkEligibility({ ...ok, hasActiveCheckIn: true })).toMatchObject({ reason: 'active_checkin' });
  });

  it('blocks inside quiet hours', () => {
    // 05:00 in New York → 10:00 UTC
    expect(
      checkEligibility({ ...ok, now: new Date('2026-03-10T09:00:00Z') }),
    ).toMatchObject({ reason: 'quiet_hours' });
  });
});
