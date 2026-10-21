import { describe, expect, it } from 'vitest';
import {
  confirmNutritionProposal,
  getNutritionThread,
  isLayer1Reason,
  sendNutritionTurn,
} from './kernel.js';
import type { PrismaClient } from '@prisma/client';

const empty = {} as PrismaClient;

describe('nutrition assistant kernel gates', () => {
  it('treats SCOFF and medical-supervision as Layer 1', () => {
    expect(isLayer1Reason('EATING_DISORDER_SCREEN')).toBe(true);
    expect(isLayer1Reason('MEDICAL_SUPERVISION')).toBe(true);
    expect(isLayer1Reason(null)).toBe(false);
    expect(isLayer1Reason('OTHER')).toBe(false);
  });

  it('returns paused without touching the database when the env kill switch is off', async () => {
    const thread = await getNutritionThread(empty, 'u1', 'en');
    expect(thread.state).toBe('paused');
    const send = await sendNutritionTurn(empty, 'u1', { message: 'What’s left today?', lang: 'en' });
    expect(send.state).toBe('paused');
    const confirm = await confirmNutritionProposal(empty, 'u1', 'p1', 'en');
    expect(confirm.ok).toBe(false);
  });
});
