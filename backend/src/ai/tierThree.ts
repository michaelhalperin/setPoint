import type Anthropic from '@anthropic-ai/sdk';
import { z } from 'zod';
import type { Goal } from '../engine/types.js';
import { MANAGER_VOICE_MODEL } from './models.js';

export type ConversationTurn = { role: 'user' | 'assistant'; content: string };

export type ConversationOutcome =
  | 'NONE'
  | 'ADJUST_PLAN'
  | 'PAUSE_CHECKINS'
  | 'SUGGEST_PROFESSIONAL';

export type TierThreeReply = {
  reply: string;
  outcome: ConversationOutcome;
  /** True when the conversation should close. */
  done: boolean;
};

export type TierThreeContext = { goal: Goal; recentMisses: number };

export interface TierThreeConversant {
  opener(context: TierThreeContext): string;
  respond(history: ConversationTurn[], context: TierThreeContext): Promise<TierThreeReply>;
}

/**
 * The tier-3 "this isn't working right now" conversation (plan §2). Bounded:
 * the only outcomes are adjust the plan, pause check-ins, or point to
 * professional support — never open-ended chat, and nothing shame-adjacent
 * given the §3 screening.
 */
const SYSTEM = [
  "You are SetPoint's manager voice, checking in after the user has missed several meals in a row.",
  'This is a short conversation, not a chat. Your only goals, in order of preference based on what they say:',
  '  1. adjust the plan — a lower daily target, different meal times, or fewer check-ins',
  '  2. pause check-ins for a while',
  '  3. if they mention struggling with eating, food, or their body, gently suggest talking to a professional',
  'Rules: 1–2 sentences per reply. Warm, direct, never a lecture. Never mention weight, guilt, or failure.',
  'After at most 3 of your replies, land on an outcome and set done=true.',
  'Always call reply_to_user.',
].join('\n');

const replyTool: Anthropic.Tool = {
  name: 'reply_to_user',
  description: 'Send your reply and the current outcome of the conversation.',
  input_schema: {
    type: 'object',
    additionalProperties: false,
    properties: {
      reply: { type: 'string' },
      outcome: {
        type: 'string',
        enum: ['NONE', 'ADJUST_PLAN', 'PAUSE_CHECKINS', 'SUGGEST_PROFESSIONAL'],
      },
      done: { type: 'boolean' },
    },
    required: ['reply', 'outcome', 'done'],
  },
};

const replySchema = z.object({
  reply: z.string().min(1),
  outcome: z.enum(['NONE', 'ADJUST_PLAN', 'PAUSE_CHECKINS', 'SUGGEST_PROFESSIONAL']).default('NONE'),
  done: z.coerce.boolean().default(false),
});

export const fallbackTierThree: TierThreeConversant = {
  opener() {
    return "This hasn't been working the last few days. Want to lower the target, shift your check-ins, or pause them for a bit?";
  },
  async respond(history) {
    const last = history.filter((t) => t.role === 'user').at(-1)?.content.toLowerCase() ?? '';
    const assistantTurns = history.filter((t) => t.role === 'assistant').length;

    if (/(struggl|hard time|can't eat|cant eat|disorder|therap)/.test(last)) {
      return {
        reply:
          "Thanks for telling me. SetPoint will keep tracking without pushing — and talking to a professional can really help. The NEDA helpline is a good place to start.",
        outcome: 'SUGGEST_PROFESSIONAL',
        done: true,
      };
    }
    if (/(pause|stop|break|too much|leave me)/.test(last)) {
      return {
        reply: "Done — check-ins are paused. Turn them back on in Settings whenever you're ready.",
        outcome: 'PAUSE_CHECKINS',
        done: true,
      };
    }
    if (assistantTurns >= 2) {
      return {
        reply: "Let's ease off the target for now and see how the week goes. You can fine-tune it in Settings.",
        outcome: 'ADJUST_PLAN',
        done: true,
      };
    }
    return {
      reply: 'What would make this easier — a smaller target, later check-ins, or a pause?',
      outcome: 'NONE',
      done: false,
    };
  },
};

export function createAiTierThree(
  client: Anthropic,
  fallback: TierThreeConversant = fallbackTierThree,
): TierThreeConversant {
  return {
    opener: (ctx) => fallback.opener(ctx),
    async respond(history, context) {
      try {
        const message = await client.messages.create({
          model: MANAGER_VOICE_MODEL,
          max_tokens: 400,
          system: SYSTEM,
          tools: [replyTool],
          tool_choice: { type: 'tool', name: 'reply_to_user' },
          messages: [
            {
              role: 'user',
              content: JSON.stringify({
                goal: context.goal.toLowerCase(),
                recentMisses: context.recentMisses,
                conversation: history,
              }),
            },
          ],
        });

        const toolUse = message.content.find((b) => b.type === 'tool_use');
        const parsed = toolUse ? replySchema.safeParse(toolUse.input) : undefined;
        if (!parsed?.success) return fallback.respond(history, context);
        return parsed.data;
      } catch (err) {
        console.error('[tierThree] falling back', err);
        return fallback.respond(history, context);
      }
    },
  };
}
