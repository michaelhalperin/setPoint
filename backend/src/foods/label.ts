/**
 * Reads a photographed nutrition label into per-100 g facts, so a barcode that
 * no database knows can be filled once and found by everyone after.
 */
import type Anthropic from '@anthropic-ai/sdk';
import { z } from 'zod';
import { LABEL_READ_MODEL } from '../ai/models.js';
import type { MealImage } from '../ai/parseMeal.js';
import type { BarcodeFoodFacts } from './barcode.js';

export type LabelReader = (image: MealImage) => Promise<BarcodeFoodFacts | null>;

export class LabelReadError extends Error {}

const RECORD_LABEL_TOOL: Anthropic.Tool = {
  name: 'record_label',
  description: 'Record what the photographed food package says about the product and its nutrition per 100 g.',
  input_schema: {
    type: 'object',
    additionalProperties: false,
    properties: {
      readable: {
        type: 'boolean',
        description: 'false when the photo is not a nutrition label or the energy value cannot be read',
      },
      name: {
        type: 'string',
        description: 'product name as printed, in the pack’s language — the name only, without weight, serving size or slogans; empty if not visible',
      },
      brand: {
        type: 'string',
        description: 'brand or manufacturer as printed; empty unless one is clearly shown — never a flavour or food word',
      },
      servingG: { type: ['number', 'null'], description: 'grams (or ml) in one serving if printed, else null' },
      kcal100g: { type: 'number' },
      proteinG100g: { type: 'number' },
      carbsG100g: { type: 'number' },
      fatG100g: { type: 'number' },
    },
    required: ['readable', 'name', 'brand', 'servingG', 'kcal100g', 'proteinG100g', 'carbsG100g', 'fatG100g'],
  },
};

const SYSTEM = [
  'You read the nutrition facts panel on a photographed food package.',
  'Report values per 100 g (or 100 ml). If the panel only gives values per serving and states the serving weight, convert to per 100 g; if it gives both, use the per-100 g column.',
  'Energy is in kcal: when only kJ is printed, divide by 4.184. Carbohydrates means total carbohydrates.',
  'Labels may be in any language — e.g. Hebrew "ערכים תזונתיים ב-100 גרם", "אנרגיה (קלוריות)", "חלבונים", "פחמימות", "שומנים".',
  'Copy numbers exactly as printed; never estimate a value that is not on the label. If energy is unreadable or this is not a nutrition label, set readable to false.',
  'Always call the record_label tool.',
].join(' ');

const recordLabelSchema = z.object({
  readable: z.boolean(),
  name: z.string().default(''),
  brand: z.string().default(''),
  servingG: z.coerce.number().positive().max(5000).nullable().catch(null),
  kcal100g: z.coerce.number().nonnegative().max(950),
  proteinG100g: z.coerce.number().nonnegative().max(100).catch(0),
  carbsG100g: z.coerce.number().nonnegative().max(100).catch(0),
  fatG100g: z.coerce.number().nonnegative().max(100).catch(0),
});

const round1 = (n: number): number => Math.round(n * 10) / 10;

/** Null when the photo isn't a readable label; throws when the model misbehaves. */
export function createLabelReader(client: Anthropic): LabelReader {
  return async (image) => {
    const message = await client.messages.create({
      model: LABEL_READ_MODEL,
      max_tokens: 512,
      system: SYSTEM,
      tools: [RECORD_LABEL_TOOL],
      tool_choice: { type: 'tool', name: 'record_label' },
      messages: [
        {
          role: 'user',
          content: [
            { type: 'image', source: { type: 'base64', media_type: image.mediaType, data: image.data } },
            { type: 'text', text: 'Read this nutrition label.' },
          ],
        },
      ],
    });

    const toolUse = message.content.find((b) => b.type === 'tool_use');
    if (!toolUse || toolUse.name !== 'record_label') throw new LabelReadError('model did not return a record_label call');
    const parsed = recordLabelSchema.safeParse(toolUse.input);
    if (!parsed.success) return null;
    return labelFacts(parsed.data);
  };
}

export type LabelReading = z.infer<typeof recordLabelSchema>;

/** Sanity-checks a reading and shapes it for the barcode cache. Pure. */
export function labelFacts(d: LabelReading): BarcodeFoodFacts | null {
  if (!d.readable || d.kcal100g <= 0) return null;
  // Macros can't outweigh the 100 g they are part of.
  if (d.proteinG100g + d.carbsG100g + d.fatG100g > 105) return null;
  const brand = d.brand.trim().slice(0, 120) || null;
  return {
    name: (d.name.trim() || brand || 'Scanned product').slice(0, 200),
    brand,
    servingG: d.servingG,
    kcal100g: Math.round(d.kcal100g),
    proteinG100g: round1(d.proteinG100g),
    carbsG100g: round1(d.carbsG100g),
    fatG100g: round1(d.fatG100g),
  };
}
