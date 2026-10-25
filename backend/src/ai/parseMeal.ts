import type Anthropic from '@anthropic-ai/sdk';
import { z } from 'zod';
import { MEAL_PARSE_MODEL, MEAL_PHOTO_MODEL } from './models.js';

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
  /** 0–1 — model self-score, not a diagnosis. */
  confidence: number;
  /** Honest label: high | estimate | review. */
  quality: 'high' | 'estimate' | 'review';
  needsReview: boolean;
  summary: string;
  notes?: string;
};

export type MealParser = (input: MealParseInput) => Promise<ParsedMeal>;

export class MealParseError extends Error {}

const RECORD_MEAL_TOOL: Anthropic.Tool = {
  name: 'record_meal',
  description: 'Record each food in the meal with its portion in grams and its nutrition per 100 g.',
  input_schema: {
    type: 'object',
    additionalProperties: false,
    properties: {
      observations: {
        type: 'string',
        description:
          'Before any numbers: what is on the plate, the size cues you are using (plate, cutlery, hand, cup, packaging), and how each food looks cooked.',
      },
      items: {
        type: 'array',
        description: 'Each distinct food, drink, sauce or added fat — one entry per component.',
        items: {
          type: 'object',
          additionalProperties: false,
          properties: {
            name: { type: 'string', description: 'specific, with preparation, e.g. "Grilled chicken thigh, skin on"' },
            quantity: { type: 'string', description: 'human portion, e.g. "1 thigh", "1½ cups", "2 tbsp"' },
            grams: { type: 'number', description: 'estimated edible weight of this portion in grams (ml for drinks)' },
            kcalPer100g: { type: 'number' },
            proteinPer100g: { type: 'number' },
            carbsPer100g: { type: 'number' },
            fatPer100g: { type: 'number' },
          },
          required: ['name', 'quantity', 'grams', 'kcalPer100g', 'proteinPer100g', 'carbsPer100g', 'fatPer100g'],
        },
      },
      confidence: {
        type: 'number',
        description: '0–1: how sure you are of the foods AND the portion sizes together',
      },
      summary: { type: 'string', description: 'short human label for the meal, e.g. "Chicken burrito bowl"' },
      notes: { type: 'string', description: 'the assumptions a person might want to correct (portion, oil, sauce)' },
    },
    required: ['observations', 'items', 'confidence', 'summary'],
  },
};

/**
 * Photos go to a model without forced tool use, so the same shape is asked for
 * as structured output instead — the API guarantees JSON matching it.
 */
const MEAL_JSON_SCHEMA = {
  ...RECORD_MEAL_TOOL.input_schema,
  required: ['observations', 'items', 'confidence', 'summary', 'notes'],
};

const SYSTEM_TEXT = [
  'You are a registered dietitian estimating what someone ate from their description.',
  'Use realistic everyday portions; if the input is ambiguous, choose the most typical interpretation and record the assumption in `notes`.',
  'For each component give its portion in grams and its nutrition per 100 g for that prepared form (cooked, not raw), from standard food composition data.',
  'Include cooking fat, sauces, dressings and drinks the description implies. If you are unsure, lower confidence rather than inventing certainty.',
  'Always call the record_meal tool.',
].join(' ');

const SYSTEM_PHOTO = [
  'You are a registered dietitian who estimates meals from photos for an app whose users train hard and need accurate calorie counts.',
  'Work in this order, writing it in `observations` first:',
  '1. Identify every component on the plate, including sauces, dressings, toppings, spreads, garnish with real calories, and any drink in frame. Name foods specifically, with their preparation (fried, grilled, roasted, creamy, breaded).',
  '2. Find a size reference — a dinner plate is about 26 cm across, a side plate 20 cm, a bowl about 15 cm, a fork about 19 cm, a palm about 9 cm, a can 330 ml — and judge each portion against it, including how high food is piled.',
  '3. Estimate each portion as edible grams. Typical anchors: a cooked chicken breast is 150–200 g, a fist of cooked rice or pasta about 150 g, a slice of bread 30–40 g, a tablespoon of oil 14 g, a restaurant burger patty 110–170 g.',
  '4. Give nutrition per 100 g for the food as prepared, from standard composition data (USDA FoodData Central values).',
  'Account for calories people cannot see: oil absorbed by fried or sautéed food, butter on vegetables or bread, oil in dressings and stir-fries, sugar in sauces and drinks — add them as their own item when they are likely. Restaurant and takeaway portions run larger and richer than home cooking.',
  'If the person added a description, trust it for what the food is and how much there is.',
  'Do not round everything to neat numbers or understate portions to be safe; give your best central estimate and express doubt through `confidence` and `notes`.',
].join(' ');

const recordMealSchema = z.object({
  observations: z.string().optional(),
  items: z
    .array(
      z.object({
        name: z.string().default('item'),
        quantity: z.string().default(''),
        grams: z.coerce.number().positive().max(5000).optional().catch(undefined),
        kcalPer100g: z.coerce.number().nonnegative().max(950).optional().catch(undefined),
        proteinPer100g: z.coerce.number().nonnegative().max(100).optional().catch(undefined),
        carbsPer100g: z.coerce.number().nonnegative().max(100).optional().catch(undefined),
        fatPer100g: z.coerce.number().nonnegative().max(100).optional().catch(undefined),
        // Older shape: portion totals given directly.
        kcal: z.coerce.number().nonnegative().optional(),
        proteinG: z.coerce.number().nonnegative().optional(),
        carbsG: z.coerce.number().nonnegative().optional(),
        fatG: z.coerce.number().nonnegative().optional(),
      }),
    )
    .default([]),
  totalKcal: z.coerce.number().nonnegative().optional(),
  totalProteinG: z.coerce.number().nonnegative().default(0),
  totalCarbsG: z.coerce.number().nonnegative().default(0),
  totalFatG: z.coerce.number().nonnegative().default(0),
  confidence: z.coerce.number().default(0.5),
  summary: z.string().default('meal'),
  notes: z.string().optional(),
});

type RecordedItem = z.infer<typeof recordMealSchema>['items'][number];

const round1 = (n: number): number => Math.round(n * 10) / 10;

/**
 * Portion macros from grams × per-100 g values, so the calories always follow
 * the portion the model judged. Falls back to directly given totals.
 */
export function itemFromRecord(i: RecordedItem): ParsedMealItem | null {
  if (i.grams != null && i.kcalPer100g != null) {
    const f = i.grams / 100;
    return {
      name: i.name,
      quantity: quantityWithGrams(i.quantity, i.grams),
      kcal: Math.round(i.kcalPer100g * f),
      proteinG: round1((i.proteinPer100g ?? 0) * f),
      carbsG: round1((i.carbsPer100g ?? 0) * f),
      fatG: round1((i.fatPer100g ?? 0) * f),
    };
  }
  if (i.kcal == null) return null;
  return {
    name: i.name,
    quantity: i.quantity,
    kcal: Math.round(i.kcal),
    proteinG: round1(i.proteinG ?? 0),
    carbsG: round1(i.carbsG ?? 0),
    fatG: round1(i.fatG ?? 0),
  };
}

/** "1 thigh" → "1 thigh · ~140 g", so the portion a person corrects is visible. */
function quantityWithGrams(quantity: string, grams: number): string {
  const q = quantity.trim();
  const g = `~${Math.round(grams)} ${/\bml\b/i.test(q) ? 'ml' : 'g'}`;
  if (!q) return g;
  if (/\d\s*(g|ml)\b/i.test(q)) return q;
  return `${q} · ${g}`;
}

function buildContent(input: MealParseInput): Anthropic.MessageParam['content'] {
  if (input.image) {
    const instruction = input.text
      ? `Estimate this meal. The person says: ${input.text}`
      : 'Estimate the meal in this photo.';
    return [
      { type: 'image', source: { type: 'base64', media_type: input.image.mediaType, data: input.image.data } },
      { type: 'text', text: instruction },
    ];
  }
  return `Meal description: ${input.text}`;
}

/** Text: the fast pin with a forced record_meal call. */
export function mealTextRequest(input: MealParseInput): Anthropic.MessageCreateParamsNonStreaming {
  return {
    model: MEAL_PARSE_MODEL,
    max_tokens: 1024,
    system: SYSTEM_TEXT,
    tools: [RECORD_MEAL_TOOL],
    tool_choice: { type: 'tool', name: 'record_meal' },
    messages: [{ role: 'user', content: buildContent(input) }],
  };
}

/**
 * Photo: the stronger model thinks it through (adaptive thinking, medium effort)
 * and answers as structured output. A safety false positive on a food photo is
 * retried on Anthropic's default fallback model instead of failing the log.
 */
export function mealPhotoRequest(input: MealParseInput): Anthropic.Beta.MessageCreateParamsNonStreaming {
  return {
    model: MEAL_PHOTO_MODEL,
    max_tokens: 16000,
    betas: ['server-side-fallback-2026-07-01'],
    fallbacks: 'default',
    system: SYSTEM_PHOTO,
    output_config: { effort: 'medium', format: { type: 'json_schema', schema: MEAL_JSON_SCHEMA } },
    messages: [{ role: 'user', content: buildContent(input) as Anthropic.Beta.BetaMessageParam['content'] }],
  };
}

/** The record the model returned: a tool call (text) or the JSON answer (photo). */
async function recordFor(client: Anthropic, input: MealParseInput): Promise<unknown> {
  if (!input.image) {
    const message = await client.messages.create(mealTextRequest(input));
    const toolUse = message.content.find((b) => b.type === 'tool_use');
    if (!toolUse || toolUse.name !== 'record_meal') {
      throw new MealParseError('model did not return a record_meal call');
    }
    return toolUse.input;
  }
  const message = await client.beta.messages.create(mealPhotoRequest(input));
  if (message.stop_reason === 'refusal') throw new MealParseError('the photo was declined');
  const text = message.content.find((b) => b.type === 'text');
  if (!text || text.type !== 'text') throw new MealParseError('model returned no meal record');
  try {
    return JSON.parse(text.text);
  } catch {
    throw new MealParseError('model returned an unreadable meal record');
  }
}

/** Builds a Claude-backed meal parser (plan §7 — cheap/fast model). */
export function createMealParser(client: Anthropic): MealParser {
  return async (input) => {
    if (!input.text && !input.image) throw new MealParseError('nothing to parse');

    const parsed = recordMealSchema.safeParse(await recordFor(client, input));
    if (!parsed.success) {
      throw new MealParseError(`unusable record_meal payload: ${parsed.error.issues[0]?.message ?? 'invalid'}`);
    }

    const d = parsed.data;
    const items = d.items.map(itemFromRecord).filter((i): i is ParsedMealItem => i !== null);
    if (items.length === 0 && d.totalKcal == null) {
      throw new MealParseError('unusable record_meal payload: no items and no total');
    }
    // Per-item grams make the item sum the estimate; a model total is only the
    // fallback for the older shape.
    const reconciled =
      d.totalKcal == null
        ? { totals: sumItems(items), usedItemSum: false }
        : reconcileMealTotals(items, {
            kcal: Math.round(d.totalKcal),
            proteinG: round1(d.totalProteinG),
            carbsG: round1(d.totalCarbsG),
            fatG: round1(d.totalFatG),
          });
    const confidence = Math.min(1, Math.max(0, d.confidence));
    const quality = estimateQuality(confidence, Boolean(input.image), reconciled.usedItemSum);
    return {
      items,
      ...reconciled.totals,
      confidence,
      quality,
      needsReview: quality === 'review',
      summary: d.summary,
      notes: d.notes,
    };
  };
}

function sumItems(items: ParsedMealItem[]): { kcal: number; proteinG: number; carbsG: number; fatG: number } {
  return {
    kcal: Math.round(items.reduce((a, i) => a + i.kcal, 0)),
    proteinG: round1(items.reduce((a, i) => a + i.proteinG, 0)),
    carbsG: round1(items.reduce((a, i) => a + i.carbsG, 0)),
    fatG: round1(items.reduce((a, i) => a + i.fatG, 0)),
  };
}

export function reconcileMealTotals(
  items: ParsedMealItem[],
  totals: { kcal: number; proteinG: number; carbsG: number; fatG: number },
): { totals: typeof totals; usedItemSum: boolean } {
  if (items.length === 0) return { totals, usedItemSum: false };
  const sum = {
    kcal: items.reduce((a, i) => a + i.kcal, 0),
    proteinG: round1(items.reduce((a, i) => a + i.proteinG, 0)),
    carbsG: round1(items.reduce((a, i) => a + i.carbsG, 0)),
    fatG: round1(items.reduce((a, i) => a + i.fatG, 0)),
  };
  const denom = Math.max(totals.kcal, sum.kcal, 1);
  if (Math.abs(sum.kcal - totals.kcal) / denom > 0.15) {
    return { totals: { ...sum, kcal: Math.round(sum.kcal) }, usedItemSum: true };
  }
  return { totals, usedItemSum: false };
}

export function estimateQuality(
  confidence: number,
  fromPhoto: boolean,
  usedItemSum: boolean,
): 'high' | 'estimate' | 'review' {
  if (fromPhoto && confidence < 0.45) return 'review';
  if (usedItemSum || confidence < 0.6) return 'estimate';
  return 'high';
}
