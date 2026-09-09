import type Anthropic from '@anthropic-ai/sdk';
import { MANAGER_VOICE_MODEL } from '../ai/models.js';
import type { ManagerVoice, ManagerVoiceContext } from './types.js';

/**
 * Tone guardrails per plan §6 and §3 (the ED screening means nothing here may
 * read as shaming). The model writes *what* the check-in says, never *whether*
 * it fires (§7).
 */
const SYSTEM = [
  'You write one short push-notification line for SetPoint, an app that helps people eat enough for their goal.',
  'Voice: a manager, not a punisher — assertive, specific, warm, matter-of-fact.',
  'Hard rules:',
  '- Exactly one sentence, under 140 characters. No emoji. No exclamation marks.',
  '- Never mention weight, body image, guilt, willpower, "failure", "cheating", "slipping", or being "behind" as a judgement.',
  '- Never diagnose or reference eating patterns clinically.',
  '- If a specific food suggestion is given, use it as the concrete action.',
  '- Use only numbers provided to you; invent none.',
  'Return only the sentence.',
].join('\n');

function promptFor(ctx: ManagerVoiceContext): string {
  return JSON.stringify({
    tone: ctx.tier >= 2 ? 'firm' : 'gentle',
    goal: ctx.goal.toLowerCase(),
    hoursSinceLastMeal: Math.round(ctx.hoursSinceMeal),
    caloriesToTarget: ctx.kcalGap ?? null,
    suggestion: ctx.prescriptionSummary ?? null,
  });
}

/** Claude-backed manager's voice; any failure falls back to the deterministic copy. */
export function createAiManagerVoice(client: Anthropic, fallback: ManagerVoice): ManagerVoice {
  return {
    async checkInMessage(ctx: ManagerVoiceContext): Promise<string> {
      try {
        const message = await client.messages.create({
          model: MANAGER_VOICE_MODEL,
          max_tokens: 200,
          system: SYSTEM,
          messages: [{ role: 'user', content: promptFor(ctx) }],
        });

        const text = message.content
          .filter((b) => b.type === 'text')
          .map((b) => b.text)
          .join(' ')
          .trim();

        return text || fallback.checkInMessage(ctx);
      } catch (err) {
        console.error('[managerVoice:ai] falling back to deterministic copy', err);
        return fallback.checkInMessage(ctx);
      }
    },
  };
}
