import type { Goal } from '../engine/types.js';

export type ManagerVoiceContext = {
  tier: number;
  goal: Goal;
  hoursSinceMeal: number;
  /** Meal-sized calorie target for right now, when known. */
  kcalGap: number | null;
  /** The solver's "eat this" line, e.g. "2× Hard-boiled eggs + Banana". */
  prescriptionSummary?: string | null;
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
