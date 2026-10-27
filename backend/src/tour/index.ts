import type { PrismaClient } from '@prisma/client';
import { z } from 'zod';

/**
 * The guided tour: a list of steps, each pointing at one element of the app by
 * its anchor id. The app owns the anchors (they are views it has tagged), the
 * owner edits the steps from /admin, and GET /api/tour hands them to the app.
 * A step with no anchor is shown in the middle of the screen.
 */

export const TOUR_TABS = ['today', 'train', 'progress', 'you'] as const;
export type TourTab = (typeof TOUR_TABS)[number];

/** `pad` and `radius` shape the spotlight around the element, in points. The app and the admin preview both use them. */
export const TOUR_ANCHORS = [
  { id: 'today.orb', tab: 'today', label: 'Orb and ring', pad: 8, radius: 150 },
  { id: 'today.pace', tab: 'today', label: 'Pace pill', pad: 6, radius: 24 },
  { id: 'today.next', tab: 'today', label: 'Next card', pad: 6, radius: 30 },
  { id: 'today.dots', tab: 'today', label: 'Meal dots', pad: 8, radius: 18 },
  { id: 'nav.plus', tab: 'today', label: '+ button', pad: 6, radius: 40 },
  { id: 'train.add', tab: 'train', label: 'Add session +', pad: 6, radius: 30 },
  { id: 'train.week', tab: 'train', label: 'Week card', pad: 4, radius: 30 },
  { id: 'train.day', tab: 'train', label: 'Today’s training card', pad: 4, radius: 32 },
  { id: 'progress.weight', tab: 'progress', label: 'Weight card', pad: 4, radius: 30 },
  { id: 'progress.days', tab: 'progress', label: 'Days closed', pad: 4, radius: 30 },
  { id: 'you.goal', tab: 'you', label: 'Goal card', pad: 4, radius: 30 },
  { id: 'you.setup', tab: 'you', label: 'Setup tiles', pad: 6, radius: 30 },
  { id: 'you.help', tab: 'you', label: 'How SetPoint works row', pad: 4, radius: 30 },
] as const satisfies readonly { id: string; tab: TourTab; label: string; pad: number; radius: number }[];

export type TourAnchorId = (typeof TOUR_ANCHORS)[number]['id'];
const anchorIds = TOUR_ANCHORS.map((a) => a.id) as [TourAnchorId, ...TourAnchorId[]];

const text = (max: number) => z.string().trim().min(1).max(max);

export const tourStepSchema = z.object({
  id: z.string().min(1).max(40),
  /** Which element gets the spotlight. null: a prompt in the middle of the screen. */
  anchor: z.enum(anchorIds).nullable(),
  /** The opening prompt: asks "Show me / Not now" before the tour starts. */
  welcome: z.boolean().default(false),
  title: text(60),
  body: text(260),
  he: z.object({ title: text(60), body: text(260) }).nullable().default(null),
});

export const tourSchema = z.object({
  steps: z.array(tourStepSchema).max(20),
  /** Bumped from the admin to show the tour once more to people who already saw it. */
  revision: z.number().int().min(1).default(1),
});

export type TourStep = z.infer<typeof tourStepSchema>;
export type Tour = z.infer<typeof tourSchema>;

export const TOUR_KEY = 'tour';

export const DEFAULT_TOUR: Tour = {
  revision: 1,
  steps: [
    {
      id: 'welcome', anchor: null, welcome: true,
      title: 'Welcome to SetPoint',
      body: 'A 30-second look at where everything is. You can replay it any time from the You tab.',
      he: { title: 'ברוכים הבאים ל-SetPoint', body: 'סיור של 30 שניות במה שיש ואיפה. אפשר להפעיל אותו שוב בכל רגע מלשונית אתה.' },
    },
    {
      id: 'orb', anchor: 'today.orb', welcome: false,
      title: 'Your day so far',
      body: 'The number is what you’ve eaten today. The ring fills toward today’s target.',
      he: { title: 'היום שלך עד עכשיו', body: 'המספר הוא מה שאכלת היום. הטבעת מתמלאת לקראת היעד של היום.' },
    },
    {
      id: 'next', anchor: 'today.next', welcome: false,
      title: 'One thing to do next',
      body: 'Whatever needs you right now shows up here. Log it, swap it, or top up with something easy.',
      he: { title: 'דבר אחד לעשות עכשיו', body: 'כל מה שצריך אותך כרגע מופיע כאן. תעד, החלף, או השלם עם משהו קל.' },
    },
    {
      id: 'dots', anchor: 'today.dots', welcome: false,
      title: 'Your meal times',
      body: 'Filled dots are meals you’ve had. The empty one is coming up.',
      he: { title: 'שעות הארוחות', body: 'נקודות מלאות הן ארוחות שאכלת. הריקה עוד לפניך.' },
    },
    {
      id: 'plus', anchor: 'nav.plus', welcome: false,
      title: 'Log from anywhere',
      body: 'Tap + to log a meal by text, photo or barcode.',
      he: { title: 'תעד מכל מקום', body: 'לחץ על + כדי לתעד ארוחה בטקסט, בתמונה או בברקוד.' },
    },
    {
      id: 'week', anchor: 'train.week', welcome: false,
      title: 'Plan your week',
      body: 'Your training days. Tap + at the top to add a session, and set it to repeat weekly.',
      he: { title: 'תכנן את השבוע', body: 'ימי האימון שלך. לחץ על + למעלה כדי להוסיף אימון, ואפשר להגדיר שיחזור כל שבוע.' },
    },
    {
      id: 'day', anchor: 'train.day', welcome: false,
      title: 'Training raises your target',
      body: 'On a session day you’re told how much extra to eat, and when to eat it before and after.',
      he: { title: 'אימון מעלה את היעד', body: 'ביום אימון תראה כמה עוד כדאי לאכול, ומתי לפני ואחרי.' },
    },
    {
      id: 'weight', anchor: 'progress.weight', welcome: false,
      title: 'Are you gaining?',
      body: 'Your weight against the line to your goal. Weigh in here to keep it honest.',
      he: { title: 'האם אתה עולה?', body: 'המשקל שלך מול הקו אל היעד. שקול את עצמך כאן כדי לשמור על דיוק.' },
    },
    {
      id: 'closed', anchor: 'progress.days', welcome: false,
      title: 'Did the gap close?',
      body: 'A full orb is a day you got enough. Half-filled shows how short it was.',
      he: { title: 'האם הפער נסגר?', body: 'כדור מלא הוא יום שאכלת בו מספיק. חצי מלא מראה בכמה פספסת.' },
    },
    {
      id: 'setup', anchor: 'you.setup', welcome: false,
      title: 'Make it yours',
      body: 'Meal times, appetite, foods you avoid. Change these and your plan follows.',
      he: { title: 'התאם אישית', body: 'שעות ארוחה, תיאבון, מאכלים שאתה נמנע מהם. שנה אותם והתוכנית תעקוב.' },
    },
    {
      id: 'help', anchor: 'you.help', welcome: false,
      title: 'Replay this any time',
      body: 'Open this row whenever you want the tour again.',
      he: { title: 'הפעל שוב בכל רגע', body: 'פתח את השורה הזו בכל פעם שתרצה את הסיור שוב.' },
    },
  ],
};

/** What the owner saved, or the built-in tour when nothing is saved or what's saved no longer parses. */
export async function loadTour(prisma: PrismaClient): Promise<Tour> {
  const row = await prisma.appConfig.findUnique({ where: { key: TOUR_KEY } });
  const parsed = row ? tourSchema.safeParse(row.value) : null;
  return parsed?.success ? parsed.data : DEFAULT_TOUR;
}

export async function saveTour(prisma: PrismaClient, tour: Tour): Promise<Tour> {
  await prisma.appConfig.upsert({
    where: { key: TOUR_KEY },
    create: { key: TOUR_KEY, value: tour },
    update: { value: tour },
  });
  return tour;
}

export async function resetTour(prisma: PrismaClient, current: Tour): Promise<Tour> {
  // Keep counting revisions so people who saw the old tour see the default once more.
  const next = { ...DEFAULT_TOUR, revision: current.revision + 1 };
  return saveTour(prisma, next);
}

/** Checks that cross steps; the per-field rules live in the schema. */
export function tourProblems(tour: Tour): string | null {
  if (tour.steps.filter((s) => s.welcome).length > 1) return 'Only one step can be the opening prompt.';
  if (tour.steps.some((s) => s.welcome && s.anchor)) return 'The opening prompt has no element.';
  if (new Set(tour.steps.map((s) => s.id)).size !== tour.steps.length) return 'Two steps share an id.';
  return null;
}
