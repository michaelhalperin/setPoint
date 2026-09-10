import type {
  DaySummaryContext,
  HomeNoteContext,
  ManagerVoice,
  ManagerVoiceContext,
} from './types.js';

/**
 * Deterministic copy. Tone per plan §6: a manager, not a punisher — assertive,
 * specific, never shaming. Tier 3 is a conversation, handled elsewhere.
 */
export const fallbackManagerVoice: ManagerVoice = {
  async checkInMessage(ctx: ManagerVoiceContext): Promise<string> {
    const directive = ctx.prescriptionSummary ? ` Try ${ctx.prescriptionSummary}.` : '';
    if (ctx.tier <= 1) {
      return `Time to eat.${directive || ''}`;
    }
    return `Eat now.${directive}`;
  },

  async homeNote(ctx: HomeNoteContext): Promise<string> {
    const remaining = Math.round(ctx.remainingKcal);
    const size = mealSize(remaining, ctx.nextMeal);
    const meal = ctx.nextMeal;

    if (ctx.hasActiveCheckIn) {
      return `Open check-in: log a meal or use its suggestion.`;
    }

    if (ctx.mealsToday === 0) {
      if (meal === 'breakfast') {
        return `${Math.round(ctx.targetKcal)} kcal today. Breakfast: ~${size} kcal.`;
      }
      if (meal === 'lunch') {
        return `Nothing logged. Lunch: ~${size} kcal.`;
      }
      return `Nothing logged. Dinner: ~${size} kcal.`;
    }

    if (ctx.state === 'over') {
      return `Over target. Continue tomorrow.`;
    }

    if (ctx.state === 'on_track') {
      return `On track. Next: ${meal}.`;
    }

    const hours = ctx.hoursSinceMeal;
    if (hours != null && hours >= 5) {
      return `${Math.round(hours)} hours since eating. ${remaining} kcal left; next meal ~${size}.`;
    }

    const protein = ctx.remainingProteinG;
    if (protein != null && protein >= 50) {
      return `${remaining} kcal · ${Math.round(protein)} g protein left.`;
    }

    return `${remaining} kcal left. ${cap(meal)}: ~${size} kcal.`;
  },

  async daySummary(ctx: DaySummaryContext): Promise<string> {
    switch (ctx.kind) {
      case 'MISSED':
        return `Nothing logged.`;
      case 'UNDER':
        return `${Math.round(ctx.kcalTarget - ctx.kcalConsumed)} kcal under target.`;
      case 'OVER':
        return `Over target.`;
      default:
        return `On target.`;
    }
  },
};

export function mealWindow(
  mins: number,
  times: { lunchMin: number; dinnerMin: number },
): HomeNoteContext['nextMeal'] {
  if (mins < times.lunchMin) return 'breakfast';
  if (mins < times.dinnerMin) return 'lunch';
  return 'dinner';
}

function mealSize(remaining: number, window: HomeNoteContext['nextMeal']): number {
  const parts = window === 'breakfast' ? 3 : window === 'lunch' ? 2 : 1;
  return Math.max(350, Math.round(remaining / parts / 50) * 50);
}

function cap(s: string): string {
  return s.charAt(0).toUpperCase() + s.slice(1);
}
