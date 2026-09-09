import type { ManagerVoice, ManagerVoiceContext } from './types.js';

/**
 * Deterministic check-in copy. Tone per plan §6: a manager, not a punisher —
 * assertive, specific, never shaming. Tier 3 is a conversation, handled
 * elsewhere, so it has no notification copy here.
 */
export const fallbackManagerVoice: ManagerVoice = {
  async checkInMessage(ctx: ManagerVoiceContext): Promise<string> {
    const gap =
      ctx.kcalGap && ctx.kcalGap > 0 ? ` You're about ${Math.round(ctx.kcalGap)} kcal short today.` : '';

    if (ctx.tier <= 1) {
      return `It's been a while since you ate.${gap} Worth grabbing something now.`;
    }
    return `You're well past your usual meal gap.${gap} Let's get food in — here's a quick option.`;
  },
};
