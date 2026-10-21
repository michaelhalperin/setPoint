import type Anthropic from '@anthropic-ai/sdk';
import type { NutritionSnapshot } from './snapshot.js';

export const SYSTEM = [
  "You are SetPoint's nutrition assistant — an AI, never a dietitian, doctor, or trainer.",
  'SetPoint helps people eat enough. Never praise a deficit, never advise eating less, never set a calorie target.',
  'You may read today\'s training bump. You must not plan sessions or tell them to skip training.',
  'Reply in the user\'s language (en or he). Warm, direct, 2–4 short sentences. Not medical, not slang-trying-to-be-a-friend.',
  'The daily snapshot is the source of truth. Do not contradict remaining kcal, restrictions, or Foods I avoid.',
  'If they ask to change check-ins, say you cannot from here — snooze or pause in You.',
  'If they ask about supplements, injuries, medical advice, or eating less, refuse and point back to Today.',
  'Always call reply_to_user. Set distress_flag true if the user message is about distress, restriction-seeking, purging, bingeing, or an eating disorder — even if indirect.',
  'When they want food, call suggest_plate. Never invent foods; the solver will pick the plate.',
].join(' ');

export const replyTool: Anthropic.Tool = {
  name: 'reply_to_user',
  description: 'Send your reply. distress_flag true discards the rest of the reply.',
  input_schema: {
    type: 'object',
    additionalProperties: false,
    properties: {
      reply: { type: 'string' },
      distress_flag: { type: 'boolean' },
    },
    required: ['reply', 'distress_flag'],
  },
};

export const plateTool: Anthropic.Tool = {
  name: 'suggest_plate',
  description: 'Ask the solver for a plate. Use requireNoCook for a 10-minute ask, requireDrinkable for a drink.',
  input_schema: {
    type: 'object',
    additionalProperties: false,
    properties: {
      requireNoCook: { type: 'boolean' },
      requireDrinkable: { type: 'boolean' },
    },
    required: ['requireNoCook', 'requireDrinkable'],
  },
};

export function snapshotPayload(snapshot: NutritionSnapshot) {
  return {
    lang: snapshot.lang,
    date: snapshot.localDate,
    timezone: snapshot.timezone,
    goal: snapshot.goal,
    remainingKcal: snapshot.remainingKcal,
    remainingProteinG: snapshot.remainingProteinG,
    consumedKcal: snapshot.consumedKcal,
    targetKcal: snapshot.targetKcal,
    restrictions: snapshot.restrictions,
    dislikedFoods: snapshot.dislikedFoods,
    drinkableOk: snapshot.drinkableOk,
    savedMeals: snapshot.savedMeals,
    todayMeals: snapshot.todayMeals,
    recentDays: snapshot.recentDays,
    trainingBumpKcal: snapshot.trainingBumpKcal,
  };
}
