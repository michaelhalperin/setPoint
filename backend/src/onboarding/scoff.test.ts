import { describe, expect, it } from 'vitest';
import { deriveEnforcement, scoffFlagged, scoffScore, type ScoffAnswers } from './scoff.js';

const answers = (n: number): ScoffAnswers => {
  const keys: (keyof ScoffAnswers)[] = [
    'makeSelfSick',
    'lostControl',
    'lostOneStone',
    'believesFat',
    'foodDominates',
  ];
  return Object.fromEntries(keys.map((k, i) => [k, i < n])) as ScoffAnswers;
};

describe('scoff', () => {
  it('scores the number of yes answers', () => {
    expect(scoffScore(answers(0))).toBe(0);
    expect(scoffScore(answers(3))).toBe(3);
  });

  it('flags at 2 or more', () => {
    expect(scoffFlagged(answers(1))).toBe(false);
    expect(scoffFlagged(answers(2))).toBe(true);
  });
});

describe('deriveEnforcement', () => {
  it('enables the forcing mechanism when nothing is flagged', () => {
    expect(deriveEnforcement(false, false)).toEqual({
      enforcementEnabled: true,
      enforcementDisabledReason: null,
    });
  });

  it('disables it for a medical supervision need — that reason wins', () => {
    expect(deriveEnforcement(true, true)).toEqual({
      enforcementEnabled: false,
      enforcementDisabledReason: 'MEDICAL_SUPERVISION',
    });
  });

  it('disables it on a positive SCOFF screen', () => {
    expect(deriveEnforcement(false, true)).toEqual({
      enforcementEnabled: false,
      enforcementDisabledReason: 'EATING_DISORDER_SCREEN',
    });
  });
});
