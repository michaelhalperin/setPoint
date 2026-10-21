import type Anthropic from '@anthropic-ai/sdk';
import { z } from 'zod';
import { EXPERT_NUTRITION_MODEL } from '../models.js';
import type { ExpertLang, TranscriptTurn } from './kinds.js';
import { plateTool, replyTool, snapshotPayload, SYSTEM } from './prompt.js';
import type { NutritionSnapshot } from './snapshot.js';
import { shapeFromMessage, type PlateShape } from './suggestPlate.js';
import { copy } from './staticCopy.js';

const replySchema = z.object({
  reply: z.string().min(1),
  distress_flag: z.coerce.boolean().default(false),
});

const plateSchema = z.object({
  requireNoCook: z.coerce.boolean().default(false),
  requireDrinkable: z.coerce.boolean().default(false),
});

export type ModelTurn = {
  reply: string;
  distressFlag: boolean;
  shape: PlateShape | null;
};

export function fallbackTurn(message: string, lang: ExpertLang): ModelTurn {
  const c = copy(lang);
  const lower = message.toLowerCase();
  if (/(check-?in|snooze|pause|תזכור)/i.test(lower)) {
    return { reply: c.offRampCheckIns, distressFlag: false, shape: null };
  }
  if (/(supplement|injury|injur|doctor|medical|תוסף|פציעה)/i.test(lower)) {
    return { reply: c.offRampMedical, distressFlag: false, shape: null };
  }
  const shape = shapeFromMessage(message);
  if (shape.requireNoCook || shape.requireDrinkable || /(left|נשאר|remaining|plate|צלחת)/i.test(lower)) {
    return { reply: c.opener, distressFlag: false, shape };
  }
  return { reply: c.opener, distressFlag: false, shape: { requireNoCook: false, requireDrinkable: false } };
}

export async function runModelTurn(
  client: Anthropic | null,
  history: TranscriptTurn[],
  snapshot: NutritionSnapshot,
  lang: ExpertLang,
): Promise<ModelTurn> {
  const last = history.filter((t) => t.role === 'user').at(-1)?.content ?? '';
  if (!client) return fallbackTurn(last, lang);

  try {
    const message = await client.messages.create({
      model: EXPERT_NUTRITION_MODEL,
      max_tokens: 600,
      system: SYSTEM,
      tools: [replyTool, plateTool],
      messages: [
        {
          role: 'user',
          content: JSON.stringify({
            snapshot: snapshotPayload(snapshot),
            conversation: history.slice(-12),
          }),
        },
      ],
    });

    let reply = '';
    let distressFlag = false;
    let shape: PlateShape | null = null;
    for (const block of message.content) {
      if (block.type !== 'tool_use') continue;
      if (block.name === 'reply_to_user') {
        const parsed = replySchema.safeParse(block.input);
        if (parsed.success) {
          reply = parsed.data.reply;
          distressFlag = parsed.data.distress_flag;
        }
      }
      if (block.name === 'suggest_plate') {
        const parsed = plateSchema.safeParse(block.input);
        if (parsed.success) shape = parsed.data;
      }
    }
    if (distressFlag) return { reply: copy(lang).distress, distressFlag: true, shape: null };
    if (!reply) return fallbackTurn(last, lang);
    if (!shape) {
      const fromText = shapeFromMessage(last);
      if (fromText.requireNoCook || fromText.requireDrinkable) shape = fromText;
    }
    return { reply, distressFlag: false, shape };
  } catch (err) {
    console.error('[experts] model fallback', err);
    return fallbackTurn(last, lang);
  }
}
