import type Anthropic from '@anthropic-ai/sdk';
import { describe, expect, it, vi } from 'vitest';
import { createAiManagerVoice } from './ai.js';
import type { ManagerVoice, ManagerVoiceContext } from './types.js';

const ctx: ManagerVoiceContext = {
  tier: 2,
  goal: 'BULK',
  hoursSinceMeal: 6.4,
  kcalGap: 500,
  prescriptionSummary: '2× Hard-boiled eggs + Banana',
};

const fallback: ManagerVoice = { checkInMessage: vi.fn(async () => 'FALLBACK LINE') };

function fakeClient(impl: () => Promise<unknown>): Anthropic {
  return { messages: { create: vi.fn(impl) } } as unknown as Anthropic;
}

describe('createAiManagerVoice', () => {
  it('returns the model text and passes the guardrail system prompt', async () => {
    const client = fakeClient(async () => ({ content: [{ type: 'text', text: 'Time to eat — 2 hard-boiled eggs and a banana.' }] }));
    const voice = createAiManagerVoice(client, fallback);

    const line = await voice.checkInMessage(ctx);
    expect(line).toBe('Time to eat — 2 hard-boiled eggs and a banana.');

    const call = (client.messages.create as ReturnType<typeof vi.fn>).mock.calls[0]![0];
    expect(call.system).toMatch(/manager, not a punisher/i);
    expect(call.system).toMatch(/never mention weight/i);
    expect(fallback.checkInMessage).not.toHaveBeenCalled();
  });

  it('falls back when the model call throws', async () => {
    const voice = createAiManagerVoice(
      fakeClient(async () => {
        throw new Error('rate limited');
      }),
      fallback,
    );
    expect(await voice.checkInMessage(ctx)).toBe('FALLBACK LINE');
  });

  it('falls back when the model returns no text', async () => {
    const voice = createAiManagerVoice(fakeClient(async () => ({ content: [] })), fallback);
    expect(await voice.checkInMessage(ctx)).toBe('FALLBACK LINE');
  });
});
