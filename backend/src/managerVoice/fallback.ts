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
      return `It's been a while since you ate.${directive || ' Worth grabbing something now.'}`;
    }
    return `You're well past your usual meal gap. Let's get food in now.${directive}`;
  },

  async homeNote(ctx: HomeNoteContext): Promise<string> {
    if (ctx.state === 'under') {
      const gap = Math.round(ctx.remainingKcal);
      return `About ${gap} kcal to go today. Keep it moving — a solid meal now makes the rest easy.`;
    }
    if (ctx.state === 'over') {
      return `A bit past target today. Nothing to fix — just steer back tomorrow.`;
    }
    return `Right on track today. Hold the line.`;
  },

  async daySummary(ctx: DaySummaryContext): Promise<string> {
    switch (ctx.kind) {
      case 'MISSED':
        return `Nothing logged. Tomorrow's a clean start.`;
      case 'UNDER':
        return `Came in ${Math.round(ctx.kcalTarget - ctx.kcalConsumed)} kcal short. Let's close that gap tomorrow.`;
      case 'OVER':
        return `Over target, but not by much. Steady as you go.`;
      default:
        return `Landed on target. That's the pattern to keep.`;
    }
  },
};
