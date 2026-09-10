import type { Goal } from '../engine/types.js';
import type { DayKind, FramingState } from '../dashboard/classify.js';

export type ManagerVoiceContext = {
  tier: number;
  goal: Goal;
  hoursSinceMeal: number;
  /** Meal-sized calorie target for right now, when known. */
  kcalGap: number | null;
  /** The solver's "eat this" line, e.g. "2× Hard-boiled eggs + Banana". */
  prescriptionSummary?: string | null;
};

export type HomeNoteContext = {
  goal: Goal;
  state: FramingState;
  consumedKcal: number;
  targetKcal: number;
  remainingKcal: number;
  remainingProteinG: number | null;
  mealsToday: number;
  /** breakfast / lunch / dinner — whichever window we're in now. */
  nextMeal: 'breakfast' | 'lunch' | 'dinner';
  hoursSinceMeal: number | null;
  hasActiveCheckIn: boolean;
};

export type DaySummaryContext = {
  goal: Goal;
  kind: DayKind;
  kcalConsumed: number;
  kcalTarget: number;
};

/**
 * Writes what the app *says* (plan §7) — never whether a check-in fires. The AI
 * implementation carries tight tone guardrails (§6, and §3: nothing may read as
 * shaming); `fallbackManagerVoice` is the deterministic stand-in.
 */
export interface ManagerVoice {
  /** The firm/gentle check-in line (§2, §5.3). */
  checkInMessage(ctx: ManagerVoiceContext): Promise<string>;
  /** The manager's-note box under the home hero stat (§5.2). */
  homeNote(ctx: HomeNoteContext): Promise<string>;
  /** The one-line summary on a settled day (§5.7). */
  daySummary(ctx: DaySummaryContext): Promise<string>;
}
