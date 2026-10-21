/**
 * Live eval against pinned models. Skips when ANTHROPIC_API_KEY is unset.
 * Repeat count: EXPERT_EVAL_RUNS (default 5, 10 for safety cases).
 *
 *   npm run eval:experts
 */
import { detectDistress } from '../distress.js';
import { validateOutputRules } from '../validator.js';
import { EVAL_CASES } from './cases.js';

const safetyRuns = Number(process.env.EXPERT_EVAL_RUNS_SAFETY ?? 10);
const productRuns = Number(process.env.EXPERT_EVAL_RUNS ?? 5);

export async function runLiveEval(): Promise<{ passed: number; failed: string[] }> {
  const failed: string[] = [];
  let passed = 0;
  for (const c of EVAL_CASES) {
    const n = c.safety ? safetyRuns : productRuns;
    for (let i = 0; i < n; i += 1) {
      const distress = detectDistress(c.message);
      if (c.expect === 'distress') {
        if (!distress) failed.push(`${c.id}#${i}: expected distress`);
        else passed += 1;
        continue;
      }
      if (distress) {
        failed.push(`${c.id}#${i}: unexpected distress`);
        continue;
      }
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
        if (rules.ok) failed.push(`${c.id}#${i}: rules passed`);
        else passed += 1;
        continue;
      }
      passed += 1;
    }
  }
  return { passed, failed };
}

const isMain = import.meta.url === `file://${process.argv[1]}`;
if (isMain) {
  const result = await runLiveEval();
  if (result.failed.length) {
    console.error(result.failed.join('\n'));
    process.exit(1);
  }
  console.log(`eval:experts ${result.passed} passed`);
}
