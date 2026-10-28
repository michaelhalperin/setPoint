import type Anthropic from '@anthropic-ai/sdk';
import { MANAGER_VOICE_MODEL } from '../ai/models.js';
import type { DaySummaryContext, HomeNoteContext, ManagerVoice } from './types.js';
import { languageInstruction } from '../i18n/index.js';

/**
 * Tone guardrails per plan §6 and §3 (the ED screening means nothing here may
 * read as shaming). The model writes *what* the copy says, never *whether* a
 * check-in fires (§7).
 */
const SYSTEM = [
  'You write one short line for SetPoint, an app that helps people eat enough for their goal.',
  'Voice: a manager, not a punisher — assertive, specific, warm, matter-of-fact.',
  'Hard rules:',
  '- Exactly one sentence, under 90 characters. Use the fewest words possible. No emoji or exclamation marks.',
  '- The screen already shows the calorie totals. Do NOT restate them or say "X kcal left / to go".',
  '- Talk about timing and rhythm: which meal is next, whether the day started late, whether they are keeping pace.',
  '- Avoid calorie figures.',
  '- Do not explain the text field. Never say "drop it in", "tell me", or "type here".',
  '- Never mention weight, body image, guilt, willpower, "failure", "cheating", "slipping", or being "behind" as a judgement.',
  '- Never diagnose or reference eating patterns clinically.',
  '- Going over target is never treated as urgent or a problem to fix.',
  '- When quietMode is true: only describe the day plainly. Do not prompt, push, suggest a target, or name a next step.',
  '- If a specific food suggestion is given, use it as the concrete action.',
  '- Use only numbers provided to you; invent none.',
  'Return only the sentence.',
].join('\n');

export function createAiManagerVoice(client: Anthropic, fallback: ManagerVoice): ManagerVoice {
  async function line(surface: string, payload: unknown, fallbackFn: () => Promise<string>, lang?: 'en' | 'he'): Promise<string> {
    try {
      const message = await client.messages.create({
        model: MANAGER_VOICE_MODEL,
        max_tokens: 200,
        system: lang === 'he' ? `${SYSTEM}\n${languageInstruction('he')}` : SYSTEM,
        messages: [{ role: 'user', content: JSON.stringify({ surface, ...(payload as object) }) }],
      });
      const text = message.content
        .filter((b) => b.type === 'text')
        .map((b) => b.text)
        .join(' ')
        .trim();
      return text || fallbackFn();
    } catch (err) {
      console.error(`[managerVoice:ai] ${surface} — falling back`, err);
      return fallbackFn();
    }
  }

  return {
    homeNote: (ctx: HomeNoteContext) =>
      line(
        'home_note',
        {
          goal: ctx.goal.toLowerCase(),
          state: ctx.state,
          quietMode: !ctx.enforcementEnabled,
          mealsToday: ctx.mealsToday,
          nextMeal: ctx.nextMeal,
          pace: ctx.paceStatus,
          hoursSinceLastMeal: ctx.hoursSinceMeal === null ? null : Math.round(ctx.hoursSinceMeal),
          hasOpenCheckIn: ctx.hasActiveCheckIn,
        },
        () => fallback.homeNote(ctx),
        ctx.lang,
      ),

    daySummary: (ctx: DaySummaryContext) =>
      line(
        'day_summary',
        {
          goal: ctx.goal.toLowerCase(),
          outcome: ctx.kind.toLowerCase(),
          consumedKcal: Math.round(ctx.kcalConsumed),
          targetKcal: Math.round(ctx.kcalTarget),
        },
        () => fallback.daySummary(ctx),
        ctx.lang,
      ),
  };
}
