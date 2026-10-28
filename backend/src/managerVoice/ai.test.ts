import type Anthropic from '@anthropic-ai/sdk';
import { describe, expect, it, vi } from 'vitest';
import { createAiManagerVoice } from './ai.js';
import type { HomeNoteContext, ManagerVoice, ManagerVoiceContext } from './types.js';

const note: HomeNoteContext = {
  goal: 'BULK', state: 'under', consumedKcal: 600, targetKcal: 3000, remainingKcal: 2400,
  remainingProteinG: 120, mealsToday: 1, nextMeal: 'lunch', hoursSinceMeal: 3,
  hasActiveCheckIn: false, enforcementEnabled: true, paceStatus: 'behind',
};

const fallback: ManagerVoice = {
  checkInMessage: vi.fn(async () => 'FALLBACK LINE'),
  homeNote: vi.fn(async () => 'FALLBACK NOTE'),
  daySummary: vi.fn(async () => 'FALLBACK SUMMARY'),
};

function fakeClient(impl: () => Promise<unknown>): Anthropic {
  return { messages: { create: vi.fn(impl) } } as unknown as Anthropic;
}

describe('createAiManagerVoice', () => {
  it('returns the model text and passes the guardrail system prompt', async () => {
    const client = fakeClient(async () => ({ content: [{ type: 'text', text: 'Time to eat — 2 hard-boiled eggs and a banana.' }] }));
    const voice = createAiManagerVoice(client, fallback);

    const line = await voice.homeNote(note);
    expect(line).toBe('Time to eat — 2 hard-boiled eggs and a banana.');

    const call = (client.messages.create as ReturnType<typeof vi.fn>).mock.calls[0]![0];
    expect(call.system).toMatch(/manager, not a punisher/i);
    expect(call.system).toMatch(/never mention weight/i);
    expect(fallback.homeNote).not.toHaveBeenCalled();
  });

  it('falls back when the model call throws', async () => {
    const voice = createAiManagerVoice(
      fakeClient(async () => {
        throw new Error('rate limited');
      }),
      fallback,
    );
    expect(await voice.homeNote(note)).toBe('FALLBACK NOTE');
  });

  it('falls back when the model returns no text', async () => {
    const voice = createAiManagerVoice(fakeClient(async () => ({ content: [] })), fallback);
    expect(await voice.homeNote(note)).toBe('FALLBACK NOTE');
  });

  it('tells the model not to restate totals and to go quiet in quiet mode', async () => {
    const client = fakeClient(async () => ({ content: [{ type: 'text', text: 'Lunch next.' }] }));
    const voice = createAiManagerVoice(client, fallback);
    await voice.homeNote({
      goal: 'BULK', state: 'under', consumedKcal: 600, targetKcal: 3000, remainingKcal: 2400,
      remainingProteinG: 120, mealsToday: 1, nextMeal: 'lunch', hoursSinceMeal: 3,
      hasActiveCheckIn: false, enforcementEnabled: false, paceStatus: 'behind',
    });
    const call = (client.messages.create as ReturnType<typeof vi.fn>).mock.calls[0]![0];
    expect(call.system).toMatch(/do not restate them|X kcal left/i);
    expect(call.system).toMatch(/when quietmode is true/i);
    expect(JSON.parse(call.messages[0].content)).toMatchObject({ quietMode: true, pace: 'behind' });
    expect(JSON.parse(call.messages[0].content)).not.toHaveProperty('caloriesToTarget');
  });
});

describe('the check-in line', () => {
  const ctx: ManagerVoiceContext = {
    tier: 1, goal: 'BULK', hoursSinceMeal: 6.4, kcalGap: 600, slot: 'lunch',
    prescriptionSummary: '2× Hard-boiled eggs + Banana', paceStatus: 'behind', minutesLate: 20, mealsToday: 1,
  };
  const says = (text: string) => createAiManagerVoice(fakeClient(async () => ({ content: [{ type: 'text', text }] })), fallback);

  it('tells the model the facts, and that it may not call a behind day on pace', async () => {
    const client = fakeClient(async () => ({ content: [{ type: 'text', text: 'Six hours since you last ate: 2× hard-boiled eggs and a banana now.' }] }));
    await createAiManagerVoice(client, fallback).checkInMessage(ctx);
    const call = (client.messages.create as ReturnType<typeof vi.fn>).mock.calls.at(-1)![0];
    expect(call.system).toMatch(/never say they are on pace/i);
    expect(JSON.parse(call.messages[0].content)).toMatchObject({
      surface: 'check_in', meal: 'lunch', tone: 'gentle', paceStatus: 'behind', hoursSinceLastMeal: 6, minutesLate: 20, mealsLoggedToday: 1,
    });
  });

  it('uses a line that agrees with the facts', async () => {
    const line = 'Six hours since you last ate: 2× hard-boiled eggs and a banana now.';
    expect(await says(line).checkInMessage(ctx)).toBe(line);
  });

  it('throws away the line that said someone behind was on pace', async () => {
    expect(await says('Only 2 hours in and you are in pace.').checkInMessage(ctx)).toBe('FALLBACK LINE');
    expect(await says('You are on track, keep going.').checkInMessage(ctx)).toBe('FALLBACK LINE');
  });

  it('allows a pace claim only when the pace says so', async () => {
    const line = 'You are on pace so far, lunch next keeps it that way.';
    expect(await says(line).checkInMessage({ ...ctx, paceStatus: 'on_pace' })).toBe(line);
  });

  it('throws away invented numbers, calorie talk, shaming and time it was not given', async () => {
    expect(await says('Eat 900 kcal now to catch up on the day.').checkInMessage(ctx)).toBe('FALLBACK LINE');
    expect(await says('Nine hours since you last ate, go.').checkInMessage(ctx)).toBe('FALLBACK LINE');
    expect(await says('Be honest with your willpower and eat lunch.').checkInMessage(ctx)).toBe('FALLBACK LINE');
    expect(await says('Eat lunch! It is late.').checkInMessage(ctx)).toBe('FALLBACK LINE');
    expect(await says('Two hours since lunch time, eat something now.').checkInMessage({ ...ctx, hoursSinceMeal: null, minutesLate: null })).toBe('FALLBACK LINE');
  });

  it('falls back when the model fails or says nothing', async () => {
    const broken = createAiManagerVoice(fakeClient(async () => { throw new Error('rate limited'); }), fallback);
    expect(await broken.checkInMessage(ctx)).toBe('FALLBACK LINE');
    expect(await createAiManagerVoice(fakeClient(async () => ({ content: [] })), fallback).checkInMessage(ctx)).toBe('FALLBACK LINE');
  });
});

