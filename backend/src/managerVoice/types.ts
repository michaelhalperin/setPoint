import type { Goal } from '../engine/types.js';

export type ManagerVoiceContext = {
  tier: number;
  goal: Goal;
  hoursSinceMeal: number;
  /** Remaining calories to target for the day, when known. */
  kcalGap: number | null;
};

/**
 * Writes what a check-in *says* (plan §7) — never whether it fires. The AI
 * implementation (tight tone guardrails, no shame-adjacent language given the
 * §3 ED screening) arrives in milestone 5; `fallbackManagerVoice` is the
 * deterministic stand-in.
 */
export interface ManagerVoice {
  checkInMessage(ctx: ManagerVoiceContext): Promise<string>;
}
