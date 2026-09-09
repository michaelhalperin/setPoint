import { describe, expect, it } from 'vitest';
import { classifyDay, homeFraming } from './classify.js';

describe('classifyDay', () => {
  it('flags a day with nothing logged as MISSED', () => {
    expect(classifyDay(0, 2500)).toBe('MISSED');
  });

  it('classifies by ratio to target', () => {
    expect(classifyDay(1900, 2500)).toBe('UNDER'); // 0.76
    expect(classifyDay(2300, 2500)).toBe('ON_TRACK'); // 0.92
    expect(classifyDay(2500, 2500)).toBe('ON_TRACK');
    expect(classifyDay(3000, 2500)).toBe('OVER'); // 1.2
  });
});

describe('homeFraming', () => {
  it('shows the under-eating accent and CTA when meaningfully short — any goal', () => {
    for (const goal of ['BULK', 'DIET'] as const) {
      const f = homeFraming(goal, 1200, 2500);
      expect(f.state).toBe('under');
      expect(f.accent).toBe(true);
      expect(f.primaryCta).toBe('log_meal');
      expect(f.heroKcal).toBe(1300);
    }
  });

  it('treats going over as quiet and neutral — no accent, no CTA (plan §5.2)', () => {
    const f = homeFraming('DIET', 2800, 2500);
    expect(f.state).toBe('over');
    expect(f.accent).toBe(false);
    expect(f.primaryCta).toBeNull();
    expect(f.heroKcal).toBe(-300);
  });

  it('is on-track within the neutral band around target', () => {
    const f = homeFraming('BULK', 2450, 2500);
    expect(f.state).toBe('on_track');
    expect(f.accent).toBe(false);
  });
});
