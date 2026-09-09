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
    expect(r.done).toBe(true);
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

  it('lands on adjust-plan after a couple of exchanges', async () => {
    const history: ConversationTurn[] = [
      opener,
      { role: 'user', content: 'idk' },
      { role: 'assistant', content: 'what would help?' },
      { role: 'user', content: 'maybe less' },
    ];
    const r = await fallbackTierThree.respond(history, ctx);
    expect(r.outcome).toBe('ADJUST_PLAN');
    expect(r.done).toBe(true);
  });
});
