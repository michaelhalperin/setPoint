import { env } from '../env.js';

/** Kill switch: fresh HRV/RHR never adjust scoring while this is off. */
export function wearableModifierKillSwitchOn(): boolean {
  return env.WEARABLE_MODIFIER_ENABLED === 'true';
}

/**
 * Cohort rollout. Hash the user id so assignment is stable. The kill switch
 * still wins — this only decides who *would* get the modifier.
 */
export function userInWearableCohort(userId: string, enabledOnUser: boolean): boolean {
  if (!wearableModifierKillSwitchOn()) return false;
  if (enabledOnUser) return true;
  const pct = env.WEARABLE_MODIFIER_COHORT_PERCENT;
  if (pct <= 0) return false;
  if (pct >= 100) return true;
  return hashPercent(userId) < pct;
}

function hashPercent(id: string): number {
  let h = 0;
  for (let i = 0; i < id.length; i += 1) h = (h * 31 + id.charCodeAt(i)) >>> 0;
  return h % 100;
}
