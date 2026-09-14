import { describe, expect, it } from 'vitest';
import { fallbackTierThree, type ConversationTurn } from './tierThree.js';

const ctx = { goal: 'BULK' as const, recentMisses: 3 };
const opener: ConversationTurn = { role: 'assistant', content: fallbackTierThree.opener(ctx) };

describe('fallbackTierThree', () => {
  it('pauses check-ins when the user asks for a break', async () => {
    const r = await fallbackTierThree.respond(
      [opener, { role: 'user', content: 'can you just pause this for now' }],
      ctx,
    );
    expect(r.outcome).toBe('PAUSE_CHECKINS');
    expect(r.done).toBe(false);
  });

  it('points to support when the user mentions struggling', async () => {
    const r = await fallbackTierThree.respond(
      [opener, { role: 'user', content: "I've been having a hard time with eating" }],
      ctx,
    );
    expect(r.outcome).toBe('SUGGEST_PROFESSIONAL');
  });

  it('asks a follow-up before landing on an outcome', async () => {
    const r = await fallbackTierThree.respond(
      [opener, { role: 'user', content: 'not sure' }],
      ctx,
    );
    expect(r.outcome).toBe('NONE');
    expect(r.done).toBe(false);
  });

  it('offers a lower target only when the user asks for one', async () => {
    const r = await fallbackTierThree.respond([opener, { role: 'user', content: 'can you lower my target' }], ctx);
    expect(r.outcome).toBe('EASE_TARGET');
    expect(r.done).toBe(false);
  });

  it('does not read "please" as "ease"', async () => {
    const r = await fallbackTierThree.respond([opener, { role: 'user', content: 'please just help' }], ctx);
    expect(r.outcome).toBe('NONE');
  });

  it('lands on later check-ins, never a lower target, when nothing clear was asked', async () => {
    const history: ConversationTurn[] = [
      opener,
      { role: 'user', content: 'idk' },
      { role: 'assistant', content: 'what would help?' },
      { role: 'user', content: 'not sure honestly' },
    ];
    const r = await fallbackTierThree.respond(history, ctx);
    expect(r.outcome).toBe('DELAY_CHECKINS');
    expect(r.done).toBe(false);
  });
});
