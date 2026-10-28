import type { ManagerVoiceContext } from './types.js';

/**
 * The AI's part in a check-in notification: it phrases facts the engine already has, in a voice
 * that doesn't repeat itself, and nothing more. Its answer is checked against those facts before
 * it is used (`acceptCheckInLine`); anything that claims, counts or implies what the facts don't
 * say is thrown away and the deterministic line (`checkInCopy`) goes out instead.
 */

export const CHECK_IN_SYSTEM = [
  'You write the one-sentence push notification for a SetPoint check-in. SetPoint is for people who train and find it hard to eat enough.',
  'The JSON holds the facts about this moment. Say something true and specific about it, and name the next action.',
  'Hard rules:',
  '- One sentence, at most 110 characters. No emoji, no exclamation marks, no questions.',
  '- Use only the facts. Never claim anything they do not say.',
  '- Pace: paceStatus "behind" means they have eaten less than the day needs by now. Say it plainly if it helps, without judgement. Never say they are on pace, on track, ahead, doing well, fine or good unless paceStatus is "on_pace" or "ahead".',
  '- Name the meal that slipped (meal). When hoursSinceLastMeal is given you may say how long it has been; when minutesLate is given you may say how late the meal is. Never invent a time.',
  '- When suggestion is given, make it the action, using its words and numbers as they are.',
  '- Numbers: only numbers that appear in the facts. Never write calorie totals, targets or what is "left".',
  '- Tone: a calm, warm manager. "firm" means shorter and more direct, still kind. Never shame. Never mention weight, body, willpower, guilt, failure or cheating.',
  '- Vary the wording and the order: sometimes lead with the food, sometimes with the time, sometimes with the day. Never open with a stock phrase.',
  'Examples of good lines:',
  'Lunch is running late and the day is behind: two eggs and toast gets you moving.',
  'Six hours since you last ate. A banana and a glass of milk now.',
  'Dinner time has passed. Something with protein now keeps the day close.',
  'Return only the sentence.',
].join('\n');

/** What the model is told. Rounded so it quotes numbers that are true and easy to read. */
export function checkInFacts(ctx: ManagerVoiceContext) {
  return {
    meal: ctx.slot ? ctx.slot.replace('_', ' ') : null,
    tone: ctx.tier >= 2 ? 'firm' : 'gentle',
    goal: ctx.goal.toLowerCase(),
    paceStatus: ctx.paceStatus ?? null,
    hoursSinceLastMeal: ctx.hoursSinceMeal !== null && ctx.hoursSinceMeal >= 2 ? Math.round(ctx.hoursSinceMeal) : null,
    minutesLate: ctx.minutesLate != null && ctx.minutesLate >= 10 ? Math.round(ctx.minutesLate / 5) * 5 : null,
    mealsLoggedToday: ctx.mealsToday ?? null,
    suggestion: ctx.prescriptionSummary ?? null,
  };
}

const NUMBER_WORDS: Record<string, number> = {
  two: 2, three: 3, four: 4, five: 5, six: 6, seven: 7, eight: 8, nine: 9, ten: 10, eleven: 11, twelve: 12,
  thirteen: 13, fourteen: 14, fifteen: 15, sixteen: 16, twenty: 20, thirty: 30, forty: 40, fifty: 50, sixty: 60,
};

const PACE_CLAIM = /\b(on pace|in pace|on track|keeping pace|keeping up|ahead|doing (great|well)|going well|good rhythm|nailing|fine|crushing)\b/i;
const PACE_CLAIM_HE = /בקצב|על המסלול|מצוין|מעולה|יופי/;
const OFF_LIMITS = /\b(weight|willpower|guilt|fail(ed|ure)?|cheat(ed|ing)?|lazy|shame|fat|diet)\b|משקל|אשמה|כישלון|עצלן/i;

/** The model's line if it holds up against the facts, else null. */
export function acceptCheckInLine(raw: string, ctx: ManagerVoiceContext): string | null {
  const text = raw.trim().replace(/^["“]|["”]$/g, '').trim();
  if (text.length < 12 || text.length > 140) return null;
  if (/[\n!?]/.test(text) || /\p{Extended_Pictographic}/u.test(text)) return null;
  if (OFF_LIMITS.test(text)) return null;

  const facts = checkInFacts(ctx);
  const onPace = facts.paceStatus === 'on_pace' || facts.paceStatus === 'ahead';
  if (!onPace && (PACE_CLAIM.test(text) || PACE_CLAIM_HE.test(text))) return null;

  // Every number must come from the facts (hours, minutes, the plate's quantities); words like "two"
  // are fine only because digits are what can drift.
  const allowed = new Set(JSON.stringify(facts).match(/\d+/g) ?? []);
  for (const n of text.match(/\d+/g) ?? []) if (!allowed.has(n)) return null;
  for (const word of text.toLowerCase().match(/[a-z]+/g) ?? []) {
    const value = NUMBER_WORDS[word];
    if (value !== undefined && !allowed.has(String(value))) return null;
  }
  if (/\bkcal\b|calories|קלוריות/i.test(text)) return null;
  // Hours or lateness may be mentioned only when we gave them.
  if (/\bhours?\b|שעות/i.test(text) && facts.hoursSinceLastMeal === null && facts.minutesLate === null) return null;
  return text;
}
