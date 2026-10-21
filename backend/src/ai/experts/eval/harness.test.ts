import { describe, expect, it } from 'vitest';
import { detectDistress } from '../distress.js';
import { validateOutputRules } from '../validator.js';
import { EVAL_CASES } from './cases.js';

const RUNS = 1; // rules are deterministic; live eval:experts repeats 5–10 times.

describe('expert eval harness (rules floor)', () => {
  for (const c of EVAL_CASES) {
    it(`${c.id} × ${RUNS}`, () => {
      for (let i = 0; i < RUNS; i += 1) {
        const distress = detectDistress(c.message);
        if (c.expect === 'distress') {
          expect(distress, c.id).not.toBeNull();
          continue;
        }
        expect(distress, c.id).toBeNull();
        if (c.expect === 'rules_fail') {
          const rules = validateOutputRules({
            lang: 'en',
            lastUserMessage: c.message,
            assistantText: c.assistantText ?? '',
            toolArgs: c.toolArgs ?? null,
            allergenTokens: ['dairy'],
            remainingKcal: 400,
            goal: 'BULK',
          });
          expect(rules.ok, c.id).toBe(false);
        }
      }
    });
  }
});
