import type { PushPayload } from './types.js';

/** One sample per kind of notification the scoring job can send, for the admin test buttons. */
export const TEST_PUSHES = [
  { kind: 'plain', label: 'Plain alert (no extras)', tier: 1, category: undefined, plain: true, body: 'A bare notification, to tell a delivery problem from a settings one.' },
  { kind: 'meal_gentle', label: 'Meal · gentle', tier: 1, category: 'CHECK_IN', body: 'Lunch is up: rice and chicken covers about 700.' },
  { kind: 'meal_firm', label: 'Meal · firm', tier: 2, category: 'CHECK_IN', body: 'Nothing logged for lunch. Get 700 in now.' },
  { kind: 'conversation', label: 'Conversation', tier: 3, category: undefined, body: 'Change your target, timing, or pause check-ins?' },
  { kind: 'heads_up', label: 'Heads-up', tier: 1, category: 'HEADS_UP', body: 'Dinner is in an hour. Eat a little something now.' },
  { kind: 'top_up', label: 'Top-up', tier: 1, category: 'CHECK_IN', body: 'You are 400 short. A yogurt and a banana closes it.' },
  { kind: 'close', label: 'Evening close', tier: 1, category: 'CHECK_IN', body: 'One more small meal closes the day.' },
  { kind: 'pre_workout', label: 'Before training', tier: 1, category: 'CHECK_IN', body: 'Training soon. Eat something first.' },
  { kind: 'refuel', label: 'Refuel after training', tier: 1, category: 'REFUEL', body: 'You trained. Eat something now.' },
] as const satisfies readonly {
  kind: string;
  label: string;
  tier: number;
  category: PushPayload['category'];
  plain?: boolean;
  body: string;
}[];

export type TestPushKind = (typeof TEST_PUSHES)[number]['kind'];
