import { isWithinQuietHours, localMinutesOfDay } from './quietHours.js';

export type EligibilityContext = {
  now: Date;
  timezone: string;
  onboardingCompleted: boolean;
  /** SafetyScreening.enforcementEnabled — the single gate the engine reads (§3). */
  enforcementEnabled: boolean;
  checkInsPaused: boolean;
  backedOffUntil: Date | null;
  quietHoursStartMin: number;
  quietHoursEndMin: number;
  /** A PENDING check-in, or a DEFERRED one whose snooze has not yet elapsed. */
  hasActiveCheckIn: boolean;
};

export type EligibilityReason =
  | 'onboarding_incomplete'
  | 'enforcement_disabled'
  | 'checkins_paused'
  | 'backed_off'
  | 'active_checkin'
  | 'quiet_hours';

export type EligibilityResult =
  | { eligible: true }
  | { eligible: false; reason: EligibilityReason };

/**
 * Gate applied *before* any scoring (plan §2: quiet hours are "checked before
 * evaluation runs, not suppressed after"). Order is deliberate: cheap, stable
 * reasons first; the timezone calculation last.
 */
export function checkEligibility(ctx: EligibilityContext): EligibilityResult {
  if (!ctx.onboardingCompleted) return { eligible: false, reason: 'onboarding_incomplete' };
  if (!ctx.enforcementEnabled) return { eligible: false, reason: 'enforcement_disabled' };
  if (ctx.checkInsPaused) return { eligible: false, reason: 'checkins_paused' };
  if (ctx.backedOffUntil && ctx.backedOffUntil > ctx.now) {
    return { eligible: false, reason: 'backed_off' };
  }
  if (ctx.hasActiveCheckIn) return { eligible: false, reason: 'active_checkin' };

  const nowMin = localMinutesOfDay(ctx.now, ctx.timezone);
  if (isWithinQuietHours(nowMin, ctx.quietHoursStartMin, ctx.quietHoursEndMin)) {
    return { eligible: false, reason: 'quiet_hours' };
  }

  return { eligible: true };
}
