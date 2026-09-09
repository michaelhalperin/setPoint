import type Anthropic from '@anthropic-ai/sdk';
import { describe, expect, it, vi } from 'vitest';
import { MealParseError, createMealParser } from './parseMeal.js';

function fakeClient(content: unknown[]): Anthropic {
  return { messages: { create: vi.fn(async () => ({ content })) } } as unknown as Anthropic;
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
    const client = fakeClient([goodToolUse]);
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
});
