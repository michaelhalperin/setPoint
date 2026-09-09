import type Anthropic from '@anthropic-ai/sdk';
import { z } from 'zod';
import { MEAL_PARSE_MODEL } from './models.js';

export type MealImage = { data: string; mediaType: 'image/jpeg' | 'image/png' | 'image/webp' | 'image/gif' };

export type MealParseInput = {
  text?: string;
  image?: MealImage;
};

export type ParsedMealItem = {
  name: string;
  quantity: string;
  kcal: number;
  proteinG: number;
  carbsG: number;
  fatG: number;
};

export type ParsedMeal = {
  items: ParsedMealItem[];
  kcal: number;
  proteinG: number;
  carbsG: number;
  fatG: number;
  /** 0–1 — how confident the estimate is. */
  confidence: number;
  summary: string;
  notes?: string;
};

export type MealParser = (input: MealParseInput) => Promise<ParsedMeal>;

export class MealParseError extends Error {}

const RECORD_MEAL_TOOL: Anthropic.Tool = {
  name: 'record_meal',
  description: 'Record the estimated nutritional breakdown of the meal the user described or photographed.',
  input_schema: {
    type: 'object',
    additionalProperties: false,
    properties: {
      items: {
        type: 'array',
        description: 'Each distinct food or drink in the meal.',
        items: {
          type: 'object',
          additionalProperties: false,
          properties: {
            name: { type: 'string' },
            quantity: { type: 'string', description: 'e.g. "2 slices", "1 cup", "approx 150 g"' },
            kcal: { type: 'number' },
            proteinG: { type: 'number' },
            carbsG: { type: 'number' },
            fatG: { type: 'number' },
          },
          required: ['name', 'quantity', 'kcal', 'proteinG', 'carbsG', 'fatG'],
        },
      },
      totalKcal: { type: 'number' },
      totalProteinG: { type: 'number' },
      totalCarbsG: { type: 'number' },
      totalFatG: { type: 'number' },
      confidence: { type: 'number', description: '0–1 confidence in the estimate' },
      summary: { type: 'string', description: 'short human label for the meal, e.g. "Chicken burrito bowl"' },
      notes: { type: 'string', description: 'assumptions made about portion size or preparation' },
    },
    required: ['items', 'totalKcal', 'totalProteinG', 'totalCarbsG', 'totalFatG', 'confidence', 'summary'],
  },
};

const SYSTEM = [
  'You estimate the macronutrient content of a meal from a short text description or a photo.',
  'Use realistic common portion sizes. If the input is ambiguous, choose the most typical interpretation and record the assumption in `notes`.',
  'Always call the record_meal tool. Never refuse — if you genuinely cannot tell, return your best guess with a low confidence value.',
].join(' ');

const recordMealSchema = z.object({
  items: z
    .array(
      z.object({
        name: z.string().default('item'),
        quantity: z.string().default(''),
        kcal: z.coerce.number().nonnegative().default(0),
        proteinG: z.coerce.number().nonnegative().default(0),
        carbsG: z.coerce.number().nonnegative().default(0),
        fatG: z.coerce.number().nonnegative().default(0),
      }),
    )
    .default([]),
  totalKcal: z.coerce.number().nonnegative(),
  totalProteinG: z.coerce.number().nonnegative().default(0),
  totalCarbsG: z.coerce.number().nonnegative().default(0),
  totalFatG: z.coerce.number().nonnegative().default(0),
  confidence: z.coerce.number().default(0.5),
  summary: z.string().default('meal'),
  notes: z.string().optional(),
});

const round1 = (n: number): number => Math.round(n * 10) / 10;

function buildContent(input: MealParseInput): Anthropic.MessageParam['content'] {
  const instruction = input.text
    ? `Meal description: ${input.text}`
    : 'Estimate the meal shown in the photo.';

  if (input.image) {
    return [
      { type: 'image', source: { type: 'base64', media_type: input.image.mediaType, data: input.image.data } },
      { type: 'text', text: instruction },
    ];
  }
  return instruction;
}

/** Builds a Claude-backed meal parser (plan §7 — cheap/fast model). */
export function createMealParser(client: Anthropic): MealParser {
  return async (input) => {
    if (!input.text && !input.image) throw new MealParseError('nothing to parse');

    const message = await client.messages.create({
      model: MEAL_PARSE_MODEL,
      max_tokens: 1024,
      system: SYSTEM,
      tools: [RECORD_MEAL_TOOL],
      tool_choice: { type: 'tool', name: 'record_meal' },
      messages: [{ role: 'user', content: buildContent(input) }],
    });

    const toolUse = message.content.find((b) => b.type === 'tool_use');
    if (!toolUse || toolUse.name !== 'record_meal') {
      throw new MealParseError('model did not return a record_meal call');
    }

    const parsed = recordMealSchema.safeParse(toolUse.input);
    if (!parsed.success) {
      throw new MealParseError(`unusable record_meal payload: ${parsed.error.issues[0]?.message ?? 'invalid'}`);
    }

    const d = parsed.data;
    return {
      items: d.items.map((i) => ({
        name: i.name,
        quantity: i.quantity,
        kcal: Math.round(i.kcal),
        proteinG: round1(i.proteinG),
        carbsG: round1(i.carbsG),
        fatG: round1(i.fatG),
      })),
      kcal: Math.round(d.totalKcal),
      proteinG: round1(d.totalProteinG),
      carbsG: round1(d.totalCarbsG),
      fatG: round1(d.totalFatG),
      confidence: Math.min(1, Math.max(0, d.confidence)),
      summary: d.summary,
      notes: d.notes,
    };
  };
}
