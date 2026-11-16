import type Anthropic from '@anthropic-ai/sdk';
import { z } from 'zod';
import { languageInstruction, type Lang } from '../i18n/index.js';
import { MEAL_PARSE_MODEL } from './models.js';

export class TrainingParseError extends Error {}

const DAYS = ['sun', 'mon', 'tue', 'wed', 'thu', 'fri', 'sat'] as const;

/** One kind of session read from a description, with the weekdays it repeats on. */
export type ParsedTrainingSession = {
  title: string;
  kind: 'STRENGTH' | 'CARDIO' | 'MIXED';
  durationMin: number;
  /** Calendar weekdays, 1 = Sunday … 7 = Saturday (what the app plans with). */
  weekdays: number[];
  /** Minutes after midnight. */
  startMinute: number;
};

export type ParsedTraining = { sessions: ParsedTrainingSession[]; note: string | null };

const RECORD_TOOL: Anthropic.Tool = {
  name: 'record_training',
  description: 'Record the training sessions a person describes, each as a weekly pattern.',
  input_schema: {
    type: 'object',
    additionalProperties: false,
    properties: {
      sessions: {
        type: 'array',
        description: 'One entry per kind of session. A session done on several weekdays is one entry with all its days.',
        items: {
          type: 'object',
          additionalProperties: false,
          properties: {
            title: { type: 'string', description: 'What it is, 1–4 words, e.g. "Leg day" or "Easy run".' },
            kind: { type: 'string', enum: ['STRENGTH', 'CARDIO', 'MIXED'], description: 'Lifting/bodyweight = STRENGTH; running, cycling, swimming, walking = CARDIO; football, CrossFit, HIIT, classes = MIXED.' },
            durationMin: { type: 'integer', description: 'Minutes, 5–360. If none is given, the usual length for that activity.' },
            weekdays: { type: 'array', items: { type: 'string', enum: [...DAYS] }, description: 'Days of the week it happens.' },
            startTime: { type: 'string', description: 'Start as 24-hour HH:MM. If none is given: morning 07:00, evening 18:00, otherwise 18:00.' },
          },
          required: ['title', 'kind', 'durationMin', 'weekdays', 'startTime'],
        },
      },
      note: { type: 'string', description: 'One short line on any assumption made (for example a missing duration or day). Empty if none.' },
    },
    required: ['sessions'],
  },
};

const SYSTEM = [
  'You turn a person\'s plain description of their training week into planned sessions for a nutrition app.',
  'Group a repeating activity into one session with all its weekdays. "3 times a week" with no days: pick spread-out days (Mon, Wed, Fri for three).',
  'Never invent activities that were not mentioned. If a time or length is missing, use the usual one and say so in `note`.',
  'If the text does not describe any training, return an empty sessions list.',
  'Always call the record_training tool.',
].join(' ');

const recordSchema = z.object({
  sessions: z
    .array(
      z.object({
        title: z.string().default('Training'),
        kind: z.enum(['STRENGTH', 'CARDIO', 'MIXED']).catch('MIXED'),
        durationMin: z.coerce.number().catch(60),
        weekdays: z.array(z.string()).default([]),
        startTime: z.string().default('18:00'),
      }),
    )
    .default([]),
  note: z.string().optional(),
});

const MAX_SESSIONS = 8;

function minuteOf(time: string): number {
  const m = /^(\d{1,2}):(\d{2})$/.exec(time.trim());
  if (!m) return 18 * 60;
  const h = Number(m[1]);
  const min = Number(m[2]);
  if (h > 23 || min > 59) return 18 * 60;
  return h * 60 + min;
}

/** Cleans what the model returned into sessions the planner can use. */
export function normalizeTraining(raw: unknown): ParsedTraining {
  const parsed = recordSchema.safeParse(raw);
  if (!parsed.success) throw new TrainingParseError('unusable record_training payload');
  const sessions: ParsedTrainingSession[] = [];
  for (const s of parsed.data.sessions.slice(0, MAX_SESSIONS)) {
    const weekdays = [...new Set(s.weekdays.map((d) => DAYS.indexOf(d.toLowerCase().slice(0, 3) as (typeof DAYS)[number]) + 1).filter((n) => n > 0))].sort();
    if (weekdays.length === 0) continue;
    sessions.push({
      title: s.title.trim().slice(0, 40) || 'Training',
      kind: s.kind,
      durationMin: Math.min(360, Math.max(5, Math.round(s.durationMin || 60))),
      weekdays,
      startMinute: minuteOf(s.startTime),
    });
  }
  return { sessions, note: parsed.data.note?.trim() ? parsed.data.note.trim().slice(0, 200) : null };
}

export type TrainingParser = (input: { text: string; lang?: Lang }) => Promise<ParsedTraining>;

export function createTrainingParser(client: Anthropic): TrainingParser {
  return async ({ text, lang }) => {
    const system = lang === 'he' ? `${SYSTEM} ${languageInstruction('he')} Write the titles and the note in Hebrew.` : SYSTEM;
    const message = await client.messages.create({
      model: MEAL_PARSE_MODEL,
      max_tokens: 1024,
      system,
      tools: [RECORD_TOOL],
      tool_choice: { type: 'tool', name: 'record_training' },
      messages: [{ role: 'user', content: `My training: ${text}` }],
    });
    const toolUse = message.content.find((b) => b.type === 'tool_use');
    if (!toolUse || toolUse.name !== 'record_training') throw new TrainingParseError('model did not return a record_training call');
    return normalizeTraining(toolUse.input);
  };
}
