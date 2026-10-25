import type Anthropic from '@anthropic-ai/sdk';
import { describe, expect, it, vi } from 'vitest';
import { MealParseError, createMealParser, itemFromRecord, mealPhotoRequest, mealTextRequest, reconcileMealTotals } from './parseMeal.js';

function fakeClient(content: unknown[]): Anthropic {
  const create = vi.fn(async () => ({ content }));
  return { messages: { create }, beta: { messages: { create } } } as unknown as Anthropic;
}

/** A photo answer arrives as structured JSON text, not a tool call. */
function photoAnswer(record: unknown) {
  return { type: 'text', text: JSON.stringify(record) };
}

const goodToolUse = {
  type: 'tool_use',
  name: 'record_meal',
  input: {
    items: [
      { name: 'Chicken breast', quantity: '150 g', kcal: 248, proteinG: 46.5, carbsG: 0, fatG: 5.4 },
      { name: 'White rice', quantity: '1 cup', kcal: 205, proteinG: 4.3, carbsG: 45, fatG: 0.4 },
    ],
    totalKcal: 453,
    totalProteinG: 50.8,
    totalCarbsG: 45,
    totalFatG: 5.8,
    confidence: 0.72,
    summary: 'Chicken and rice',
    notes: 'assumed skinless breast',
  },
};

describe('createMealParser', () => {
  it('normalizes a well-formed record_meal call', async () => {
    const parse = createMealParser(fakeClient([goodToolUse]));
    const meal = await parse({ text: 'chicken breast and a cup of rice' });

    expect(meal.kcal).toBe(453);
    expect(meal.proteinG).toBe(50.8);
    expect(meal.confidence).toBe(0.72);
    expect(meal.quality).toBe('high');
    expect(meal.needsReview).toBe(false);
    expect(meal.summary).toBe('Chicken and rice');
    expect(meal.items).toHaveLength(2);
  });

  it('coerces stringy numbers and clamps confidence', async () => {
    const parse = createMealParser(
      fakeClient([
        {
          type: 'tool_use',
          name: 'record_meal',
          input: { items: [], totalKcal: '600', confidence: 1.8, summary: 'snack' },
        },
      ]),
    );
    const meal = await parse({ text: 'a snack' });
    expect(meal.kcal).toBe(600);
    expect(meal.confidence).toBe(1);
    expect(meal.proteinG).toBe(0);
  });

  it('sends the image as a base64 block when a photo is provided', async () => {
    const client = fakeClient([photoAnswer(goodToolUse.input)]);
    const parse = createMealParser(client);
    await parse({ image: { data: 'AAAA', mediaType: 'image/jpeg' } });

    const call = (client.messages.create as ReturnType<typeof vi.fn>).mock.calls[0]![0];
    const content = call.messages[0].content;
    expect(content[0]).toMatchObject({ type: 'image', source: { type: 'base64', media_type: 'image/jpeg' } });
  });

  it('throws when the model does not call the tool', async () => {
    const parse = createMealParser(fakeClient([{ type: 'text', text: "I can't help with that" }]));
    await expect(parse({ text: 'x' })).rejects.toBeInstanceOf(MealParseError);
  });

  it('throws on an unusable payload (missing totalKcal)', async () => {
    const parse = createMealParser(
      fakeClient([{ type: 'tool_use', name: 'record_meal', input: { summary: 'mystery' } }]),
    );
    await expect(parse({ text: 'x' })).rejects.toBeInstanceOf(MealParseError);
  });

  it('rejects empty input without calling the model', async () => {
    const client = fakeClient([goodToolUse]);
    await expect(createMealParser(client)({})).rejects.toBeInstanceOf(MealParseError);
    expect(client.messages.create).not.toHaveBeenCalled();
  });

  it('uses item sums when they disagree with the model total', () => {
    const r = reconcileMealTotals(
      [
        { name: 'a', quantity: '1', kcal: 300, proteinG: 10, carbsG: 20, fatG: 5 },
        { name: 'b', quantity: '1', kcal: 200, proteinG: 5, carbsG: 10, fatG: 2 },
      ],
      { kcal: 900, proteinG: 99, carbsG: 99, fatG: 99 },
    );
    expect(r.usedItemSum).toBe(true);
    expect(r.totals.kcal).toBe(500);
  });

  it('works portion macros out from grams and per-100 g values, and totals from the items', async () => {
    const parse = createMealParser(
      fakeClient([
        {
          type: 'text',
          text: JSON.stringify({
            observations: 'Dinner plate, one breast, rice heap the size of a fist, oil sheen.',
            items: [
              { name: 'Grilled chicken breast', quantity: '1 breast', grams: 180, kcalPer100g: 165, proteinPer100g: 31, carbsPer100g: 0, fatPer100g: 3.6 },
              { name: 'White rice, cooked', quantity: '1 cup', grams: 160, kcalPer100g: 130, proteinPer100g: 2.7, carbsPer100g: 28, fatPer100g: 0.3 },
              { name: 'Olive oil', quantity: '1 tbsp', grams: 14, kcalPer100g: 884, proteinPer100g: 0, carbsPer100g: 0, fatPer100g: 100 },
            ],
            confidence: 0.8,
            summary: 'Chicken, rice and oil',
            notes: '',
          }),
        },
      ]),
    );
    const meal = await parse({ image: { data: 'AAAA', mediaType: 'image/jpeg' } });
    expect(meal.items.map((i) => i.kcal)).toEqual([297, 208, 124]);
    expect(meal.items[0]?.quantity).toBe('1 breast · ~180 g');
    expect(meal.kcal).toBe(629);
    expect(meal.proteinG).toBe(60.1);
    expect(meal.quality).toBe('high');
  });

  it('keeps a quantity that already states its weight', () => {
    const item = itemFromRecord({ name: 'Juice', quantity: '250 ml', grams: 250, kcalPer100g: 45, proteinPer100g: 0.7, carbsPer100g: 10, fatPer100g: 0.2 });
    expect(item?.quantity).toBe('250 ml');
    expect(item?.kcal).toBe(113);
  });

  it('sends photos to the photo model as structured output, text to the fast tool call', () => {
    const photo = mealPhotoRequest({ image: { data: 'AAAA', mediaType: 'image/jpeg' }, text: 'large fries' });
    const text = mealTextRequest({ text: 'two eggs' });
    expect(photo.model).not.toBe(text.model);
    expect(photo.tool_choice).toBeUndefined();
    expect(photo.output_config?.format?.type).toBe('json_schema');
    expect(String(photo.system)).toMatch(/size reference/i);
    expect(JSON.stringify(photo.messages)).toContain('The person says: large fries');
  });

  it('turns a declined photo into a parse error', async () => {
    const create = vi.fn(async () => ({ content: [], stop_reason: 'refusal' }));
    const client = { messages: { create }, beta: { messages: { create } } } as unknown as Anthropic;
    await expect(createMealParser(client)({ image: { data: 'AAAA', mediaType: 'image/jpeg' } })).rejects.toBeInstanceOf(MealParseError);
  });
});
