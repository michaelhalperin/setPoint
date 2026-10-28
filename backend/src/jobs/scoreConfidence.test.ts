import type { PrismaClient } from '@prisma/client';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { STAPLE_FOODS } from '../data/stapleFoods.js';
import { SCORING_VERSION } from '../engine/behaviorScore.js';
import type { ManagerVoice } from '../managerVoice/types.js';
import type { PushPayload, PushSender } from '../push/types.js';
import { checkInCopy } from '../managerVoice/checkInCopy.js';
import { CHECK_IN_COPY_TIMEOUT_MS, DELIVERY_RETRY_WINDOW_MIN, runScoreConfidenceJob } from './scoreConfidence.js';

const NOW = new Date('2026-07-01T16:00:00Z'); // 12:00 in New York (EDT)
const hoursAgo = (h: number) => new Date(NOW.getTime() - h * 3_600_000);

type AnyRow = Record<string, unknown>;

/** Minimal in-memory stand-in for the slice of PrismaClient the job touches. */
function makeFakePrisma(users: AnyRow[], opts: { seedFoods?: boolean } = {}) {
  const checkIns: AnyRow[] = [];
  const confidenceScores: AnyRow[] = [];
  const escalationStates: AnyRow[] = [];
  const escalationConversations: AnyRow[] = [];
  const meals: AnyRow[] = [];
  const savedMeals: AnyRow[] = [];
  const pushTokens: AnyRow[] = [];
  const foodItems: AnyRow[] = [];
  const dietaryRestrictions: AnyRow[] = [];
  const prescriptions: AnyRow[] = [];
  const workouts: AnyRow[] = [];
  let seq = 0;
  const id = (p: string) => `${p}_${(seq += 1)}`;

  if (opts.seedFoods) {
    for (const f of STAPLE_FOODS) foodItems.push({ id: id('fi'), isStaple: true, ...f });
  }
  for (const u of users) {
    pushTokens.push({ id: id('pt'), userId: u.id, token: `tok_${u.id as string}`, kind: 'alert' });
  }

  const match = (row: AnyRow, where: AnyRow = {}): boolean =>
    Object.entries(where).every(([k, v]) => {
      if (v && typeof v === 'object') {
        const cond = v as Record<string, unknown>;
        if ('in' in cond) return (cond.in as unknown[]).includes(row[k]);
        if ('gte' in cond) return (row[k] as Date) >= (cond.gte as Date);
        if ('gt' in cond) return (row[k] as string) > (cond.gt as string);
        if ('lt' in cond) return (row[k] as number) < (cond.lt as number);
        if ('not' in cond) return row[k] !== cond.not;
      }
      return row[k] === v;
    });

  const collection = (rows: AnyRow[], prefix: string) => ({
    findMany: async ({ where, take }: { where?: AnyRow; take?: number } = {}) => {
      const found = rows.filter((r) => match(r, where));
      return take != null ? found.slice(0, take) : found;
    },
    findFirst: async ({ where }: { where?: AnyRow } = {}) => rows.find((r) => match(r, where)) ?? null,
    findUnique: async ({ where }: { where?: AnyRow } = {}) => rows.find((r) => match(r, where)) ?? null,
    create: async ({ data }: { data: AnyRow }) => {
      const row = { id: id(prefix), createdAt: NOW, updatedAt: NOW, deferCount: 0, deliveryStatus: 'CREATED', ...data };
      rows.push(row);
      return row;
    },
    update: async ({ where, data }: { where: AnyRow; data: AnyRow }) => {
      const row = rows.find((r) => match(r, where));
      if (row) Object.assign(row, data);
      return row;
    },
    updateMany: async ({ where, data }: { where: AnyRow; data: AnyRow }) => {
      let count = 0;
      for (const row of rows.filter((r) => match(r, where))) {
        Object.assign(row, data);
        count += 1;
      }
      return { count };
    },
    deleteMany: async ({ where }: { where?: AnyRow } = {}) => {
      const before = rows.length;
      for (let i = rows.length - 1; i >= 0; i -= 1) if (match(rows[i]!, where)) rows.splice(i, 1);
      return { count: before - rows.length };
    },
    upsert: async ({ where: rawWhere, create, update }: { where: AnyRow; create: AnyRow; update: AnyRow }) => {
      // Compound unique keys ({ userId_episodeKey: { userId, episodeKey } }) match on their fields.
      const where = Object.fromEntries(
        Object.entries(rawWhere).flatMap(([k, v]) =>
          k.includes('_') && v && typeof v === 'object' && !(v instanceof Date) ? Object.entries(v) : [[k, v]],
        ),
      );
      const row = rows.find((r) => match(r, where));
      if (row) {
        Object.assign(row, update);
        return row;
      }
      const created = { id: id(prefix), ...where, ...create };
      rows.push(created);
      return created;
    },
  });

  return {
    __tables: {
      checkIns,
      confidenceScores,
      escalationStates,
      escalationConversations,
      prescriptions,
      pushTokens,
      savedMeals,
      dietaryRestrictions,
    },
    user: {
      findMany: async ({ where, take }: { where?: AnyRow; take?: number } = {}) => {
        let found = users.filter((u) => u.onboarding != null);
        const idFilter = where?.id as { gt?: string } | undefined;
        if (idFilter?.gt) found = found.filter((u) => (u.id as string) > idFilter.gt!);
        return take != null ? found.slice(0, take) : found;
      },
    },
    checkIn: collection(checkIns, 'ci'),
    confidenceScore: collection(confidenceScores, 'cs'),
    escalationState: collection(escalationStates, 'es'),
    escalationConversation: collection(escalationConversations, 'ec'),
    meal: collection(meals, 'm'),
    savedMeal: collection(savedMeals, 'sm'),
    pushToken: collection(pushTokens, 'pt'),
    foodItem: collection(foodItems, 'fi'),
    dietaryRestriction: collection(dietaryRestrictions, 'dr'),
    prescription: collection(prescriptions, 'rx'),
    calendarBusyBlock: { findMany: async () => [] },
    calendarKeep: { findMany: async () => [] },
    workout: collection(workouts, 'wo'),
    dayAppetite: { findUnique: async () => null },
  };
}

function baseUser(over: AnyRow = {}): AnyRow {
  return {
    id: 'u1',
    timezone: 'America/New_York',
    createdAt: hoursAgo(1000),
    wearableModifierEnabled: false,
    onboarding: {
      mode: 'BASIC',
      goal: 'DIET',
      completedAt: hoursAgo(500),
      dailyKcalTarget: 2200,
      dailyProteinTargetG: 150,
      breakfastMin: 480,
      lunchMin: 780,
      dinnerMin: 1140,
      quietHoursStartMin: 1380,
      quietHoursEndMin: 420,
      pantryTokens: [],
      dislikedFoods: [],
      prepTimeMaxMin: null,
    },
    safetyScreening: { enforcementEnabled: true },
    escalationState: { consecutiveMisses: 0, currentTier: 1, checkInsPaused: false, backedOffUntil: null },
    biosignalState: null,
    ...over,
  };
}

const sentPushes: PushPayload[] = [];
const push: PushSender = {
  send: vi.fn(async (tokens, payload) => {
    sentPushes.push(payload);
    const n = tokens.length;
    return { attempted: n, sent: Math.max(n, 1), failed: 0, invalidTokens: [] };
  }),
};
const voice: ManagerVoice = {
  checkInMessage: vi.fn(async (ctx) => checkInCopy(ctx)),
  homeNote: vi.fn(async () => 'note'),
  daySummary: vi.fn(async () => 'summary'),
};

beforeEach(() => {
  sentPushes.length = 0;
  vi.clearAllMocks();
});

describe('runScoreConfidenceJob', () => {
  it('fires a check-in with a prescription for an eligible, badly overdue user', async () => {
    const fake = makeFakePrisma([baseUser()], { seedFoods: true });
    // No meals at all → hoursSinceMeal falls back to the 16h cap → basic score saturates.
    const summary = await runScoreConfidenceJob({
      prisma: fake as unknown as PrismaClient,
      push,
      voice,
      now: NOW,
    });

    expect(summary.scored).toBe(1);
    expect(summary.checkInsCreated).toBe(1);
    expect(summary.prescriptionsCreated).toBe(1);
    expect(fake.__tables.checkIns).toHaveLength(1);
    expect(fake.__tables.checkIns[0]).toMatchObject({ status: 'PENDING', tier: 1 });
    expect(fake.__tables.prescriptions[0]).toMatchObject({ checkInId: fake.__tables.checkIns[0]?.id, status: 'OFFERED' });
    expect(sentPushes).toHaveLength(1);
  });

  it('fires a refuel check-in after a workout with nothing logged', async () => {
    const fake = makeFakePrisma([baseUser()], { seedFoods: true });
    const now = new Date('2026-07-01T16:00:00Z');
    await fake.workout.create({
      data: {
        userId: 'u1',
        source: 'HEALTHKIT',
        kind: 'STRENGTH',
        start: new Date(now.getTime() - 110 * 60_000),
        durationMin: 60,
      },
    });
    fake.meal.create({
      data: { userId: 'u1', kcal: 500, proteinG: 30, loggedAt: new Date('2026-07-01T12:00:00Z') },
    });

    const summary = await runScoreConfidenceJob({
      prisma: fake as unknown as PrismaClient,
      push,
      voice,
      now,
    });

    expect(summary.checkInsCreated).toBe(1);
    expect(fake.__tables.checkIns[0]).toMatchObject({ kind: 'REFUEL', slot: 'refuel' });
    expect(sentPushes[0]?.category).toBe('REFUEL');
  });

  it('never suggests a restricted food after a workout', async () => {
    const fake = makeFakePrisma([baseUser()], { seedFoods: true });
    const now = new Date('2026-07-01T16:00:00Z');
    fake.__tables.dietaryRestrictions.push({ id: 'dr1', userId: 'u1', token: 'dairy', isHardExclusion: true });
    await fake.workout.create({
      data: { userId: 'u1', source: 'HEALTHKIT', kind: 'STRENGTH', start: new Date(now.getTime() - 110 * 60_000), durationMin: 60 },
    });
    fake.meal.create({ data: { userId: 'u1', kcal: 500, proteinG: 30, loggedAt: new Date('2026-07-01T12:00:00Z') } });

    await runScoreConfidenceJob({ prisma: fake as unknown as PrismaClient, push, voice, now });

    const rx = fake.__tables.prescriptions[0] as { items: { create: { name: string }[] } } | undefined;
    const names = (rx?.items.create ?? []).map((i) => i.name);
    expect(names.length).toBeGreaterThan(0);
    const dairy = STAPLE_FOODS.filter((f) => f.allergens.includes('dairy')).map((f) => f.name);
    expect(names.some((n) => dairy.includes(n))).toBe(false);
  });

  it('does not send a refuel check-in for a planned session nobody recorded', async () => {
    const fake = makeFakePrisma([baseUser()], { seedFoods: true });
    const now = new Date('2026-07-01T16:00:00Z');
    await fake.workout.create({
      data: { userId: 'u1', source: 'PLANNED', kind: 'STRENGTH', start: new Date(now.getTime() - 110 * 60_000), durationMin: 60 },
    });
    fake.meal.create({ data: { userId: 'u1', kcal: 500, proteinG: 30, loggedAt: new Date('2026-07-01T12:00:00Z') } });

    await runScoreConfidenceJob({ prisma: fake as unknown as PrismaClient, push, voice, now });

    expect(fake.__tables.checkIns.some((c) => c.kind === 'REFUEL')).toBe(false);
  });

  it('still fires (without a prescription) when the food list is empty', async () => {
    const fake = makeFakePrisma([baseUser()]);
    const summary = await runScoreConfidenceJob({
      prisma: fake as unknown as PrismaClient,
      push,
      voice,
      now: NOW,
    });

    expect(summary.checkInsCreated).toBe(1);
    expect(summary.prescriptionsCreated).toBe(0);
  });

  it('uses a matching saved meal as the check-in suggestion', async () => {
    const fake = makeFakePrisma([baseUser()]);
    fake.__tables.savedMeals.push({
      id: 'sm_oats',
      userId: 'u1',
      name: 'Usual oats',
      suggestSlot: 'breakfast',
      useInCheckIns: true,
      items: [{ name: 'Oats', quantity: '1 bowl', kcal: 420, proteinG: 18, carbsG: 60, fatG: 10 }],
      kcal: 420,
      proteinG: 18,
      carbsG: 60,
      fatG: 10,
      lastUsedAt: null,
      useCount: 4,
    });
    const summary = await runScoreConfidenceJob({
      prisma: fake as unknown as PrismaClient,
      push,
      voice,
      now: NOW,
    });
    expect(summary.checkInsCreated).toBe(1);
    expect(summary.prescriptionsCreated).toBe(1);
    expect(fake.__tables.prescriptions[0]).toMatchObject({ totalKcal: 420, totalProteinG: 18 });
  });

  it('skips a user inside quiet hours without scoring', async () => {
    const fake = makeFakePrisma([baseUser()]);
    const summary = await runScoreConfidenceJob({
      prisma: fake as unknown as PrismaClient,
      push,
      voice,
      now: new Date('2026-07-01T08:00:00Z'), // 04:00 in New York
    });

    expect(summary.scored).toBe(0);
    expect(summary.skipped.quiet_hours).toBe(1);
    expect(fake.__tables.checkIns).toHaveLength(0);
  });

  it('skips a user whose safety screen disabled enforcement', async () => {
    const fake = makeFakePrisma([baseUser({ safetyScreening: { enforcementEnabled: false } })]);
    const summary = await runScoreConfidenceJob({
      prisma: fake as unknown as PrismaClient,
      push,
      voice,
      now: NOW,
    });

    expect(summary.scored).toBe(0);
    expect(summary.skipped.enforcement_disabled).toBe(1);
  });

  it('escalates an overdue tier-1 deferred check-in to tier 2', async () => {
    const fake = makeFakePrisma([baseUser()]);
    fake.__tables.checkIns.push({
      id: 'ci_seed',
      userId: 'u1',
      status: 'DEFERRED',
      tier: 1,
      deferCount: 1,
      deferUntil: hoursAgo(0.5),
      deliveredAt: hoursAgo(3),
      message: 'earlier nudge',
    });

    const summary = await runScoreConfidenceJob({
      prisma: fake as unknown as PrismaClient,
      push,
      voice,
      now: NOW,
    });

    expect(summary.checkInsRedelivered).toBe(1);
    expect(summary.checkInsCreated).toBe(0);
    const seeded = fake.__tables.checkIns.find((c) => c.id === 'ci_seed');
    expect(seeded).toMatchObject({ status: 'PENDING', tier: 2 });
    expect(sentPushes).toHaveLength(1);
    expect(sentPushes[0]?.tier).toBe(2);
  });

  it('does not fire for a user who just ate', async () => {
    const fake = makeFakePrisma([baseUser()]);
    fake.meal.create({ data: { userId: 'u1', loggedAt: hoursAgo(0.5), kcal: 600, source: 'TEXT' } });

    const summary = await runScoreConfidenceJob({
      prisma: fake as unknown as PrismaClient,
      push,
      voice,
      now: NOW,
    });

    expect(summary.scored).toBe(1);
    expect(summary.checkInsCreated).toBe(0);
    expect(summary.skipped.not_due).toBe(1);
    expect(fake.__tables.confidenceScores).toHaveLength(0);
  });

  describe('on the meal schedule', () => {
    const LUNCH_PLUS_50 = new Date('2026-07-01T17:50:00Z'); // 13:50 in New York; lunch is 13:00
    const breakfast = { userId: 'u1', loggedAt: new Date('2026-07-01T12:10:00Z'), kcal: 500, proteinG: 30, source: 'TEXT' };

    it('waits until the meal time plus grace, even hours after breakfast', async () => {
      const fake = makeFakePrisma([baseUser()]);
      fake.meal.create({ data: breakfast });

      const summary = await runScoreConfidenceJob({
        prisma: fake as unknown as PrismaClient,
        push,
        voice,
        now: new Date('2026-07-01T17:40:00Z'), // 13:40 — lunch is due at 13:45
      });

      expect(summary.checkInsCreated).toBe(0);
      expect(summary.skipped.not_due).toBe(1);
    });

    it('checks in for lunch once its grace period has passed, naming the meal', async () => {
      const fake = makeFakePrisma([baseUser()], { seedFoods: true });
      fake.meal.create({ data: breakfast });

      const summary = await runScoreConfidenceJob({
        prisma: fake as unknown as PrismaClient,
        push,
        voice,
        now: LUNCH_PLUS_50,
      });

      expect(summary.checkInsCreated).toBe(1);
      expect(fake.__tables.checkIns[0]!.message).toMatch(/^Lunch slipped\. 6 hours since you last ate\./);
      expect(fake.__tables.confidenceScores[0]).toMatchObject({ firedCheckIn: true, scoringVersion: SCORING_VERSION });
    });

    it('does not create a second check-in for the same episode key', async () => {
      const fake = makeFakePrisma([baseUser()], { seedFoods: true });
      fake.meal.create({ data: breakfast });
      await runScoreConfidenceJob({
        prisma: fake as unknown as PrismaClient,
        push,
        voice,
        now: LUNCH_PLUS_50,
      });
      const again = await runScoreConfidenceJob({
        prisma: fake as unknown as PrismaClient,
        push,
        voice,
        now: LUNCH_PLUS_50,
      });
      expect(again.checkInsCreated).toBe(0);
      expect(fake.__tables.checkIns.filter((c) => c.tier !== 3)).toHaveLength(1);
    });

    it('sends the check-in as one alert, in words that state only facts', async () => {
      const fake = makeFakePrisma([baseUser()], { seedFoods: true });
      fake.meal.create({ data: breakfast });
      fake.__tables.pushTokens.push({ id: 'pt_live', userId: 'u1', token: 'live_start', kind: 'live_activity_start' });

      await runScoreConfidenceJob({ prisma: fake as unknown as PrismaClient, push, voice, now: LUNCH_PLUS_50 });

      const message = fake.__tables.checkIns[0]!.message as string;
      expect(message).toMatch(/^Lunch slipped\. 6 hours since you last ate\. Try .+\.$/);
      expect(message).not.toMatch(/pace/i);
      expect(fake.__tables.checkIns[0]).toMatchObject({ deliveryStatus: 'SENT' });
      expect(push.send).toHaveBeenCalledTimes(1);
      expect(vi.mocked(push.send).mock.calls[0]![0]).toEqual(['tok_u1']);
    });

    it('hands the voice the same pace Today shows, so the line cannot contradict it', async () => {
      const fake = makeFakePrisma([baseUser()], { seedFoods: true });
      fake.meal.create({ data: { ...breakfast, kcal: 10 } });
      await runScoreConfidenceJob({ prisma: fake as unknown as PrismaClient, push, voice, now: LUNCH_PLUS_50 });
      expect(voice.checkInMessage).toHaveBeenCalledWith(
        expect.objectContaining({ slot: 'lunch', paceStatus: 'behind', mealsToday: 0, minutesLate: 5 }),
      );
    });

    it('sends the voice\u2019s line when it has one', async () => {
      const fake = makeFakePrisma([baseUser()], { seedFoods: true });
      fake.meal.create({ data: breakfast });
      const said: ManagerVoice = { ...voice, checkInMessage: vi.fn(async () => 'Six hours since you last ate. Eggs and toast now.') };
      await runScoreConfidenceJob({ prisma: fake as unknown as PrismaClient, push, voice: said, now: LUNCH_PLUS_50 });
      expect(fake.__tables.checkIns[0]!.message).toBe('Six hours since you last ate. Eggs and toast now.');
    });

    it('sends the fixed line when the voice fails or takes too long', async () => {
      const failing = makeFakePrisma([baseUser()], { seedFoods: true });
      failing.meal.create({ data: breakfast });
      const broken: ManagerVoice = { ...voice, checkInMessage: vi.fn(async () => { throw new Error('ai down'); }) };
      await runScoreConfidenceJob({ prisma: failing as unknown as PrismaClient, push, voice: broken, now: LUNCH_PLUS_50 });
      const fixed = failing.__tables.checkIns[0]!.message as string;
      expect(fixed).toMatch(/^Lunch slipped\. 6 hours since you last ate\./);

      vi.useFakeTimers({ toFake: ['setTimeout', 'clearTimeout'] });
      try {
        const hanging = makeFakePrisma([baseUser()], { seedFoods: true });
        hanging.meal.create({ data: breakfast });
        const slow: ManagerVoice = { ...voice, checkInMessage: vi.fn(() => new Promise<string>(() => {})) };
        const run = runScoreConfidenceJob({ prisma: hanging as unknown as PrismaClient, push, voice: slow, now: LUNCH_PLUS_50 });
        await vi.advanceTimersByTimeAsync(CHECK_IN_COPY_TIMEOUT_MS + 10);
        expect((await run).checkInsCreated).toBe(1);
        expect(hanging.__tables.checkIns[0]!.message).toBe(fixed);
      } finally {
        vi.useRealTimers();
      }
    });

    it('does not claim a time since the last meal when nothing was ever logged', async () => {
      const fake = makeFakePrisma([baseUser()], { seedFoods: true });
      await runScoreConfidenceJob({ prisma: fake as unknown as PrismaClient, push, voice, now: NOW });
      expect(fake.__tables.checkIns[0]!.message as string).not.toMatch(/hours since/);
    });

    it('does not let a 10 kcal log stand in for a meal', async () => {
      const fake = makeFakePrisma([baseUser()], { seedFoods: true });
      // Breakfast was skipped; a coffee at 08:10 and a 10 kcal log just before lunch.
      fake.meal.create({ data: { ...breakfast, kcal: 10 } });
      fake.meal.create({ data: { userId: 'u1', loggedAt: new Date('2026-07-01T17:05:00Z'), kcal: 10, proteinG: 0, source: 'TEXT' } });

      const summary = await runScoreConfidenceJob({ prisma: fake as unknown as PrismaClient, push, voice, now: LUNCH_PLUS_50 });

      expect(summary.checkInsCreated).toBe(1);
      expect(fake.__tables.checkIns[0]).toMatchObject({ kind: 'MEAL' });
      // And the "time since you last ate" is not counted from the coffee.
      expect(summary.reasons.u1).toMatch(/Sent a (breakfast|lunch) check-in/);
    });

    it('says, per person, why nothing was sent', async () => {
      const fake = makeFakePrisma([baseUser()]);
      fake.meal.create({ data: breakfast });
      fake.meal.create({ data: { userId: 'u1', loggedAt: new Date('2026-07-01T17:20:00Z'), kcal: 20, proteinG: 0, source: 'TEXT' } });
      const summary = await runScoreConfidenceJob({
        prisma: fake as unknown as PrismaClient,
        push,
        voice,
        now: new Date('2026-07-01T17:40:00Z'), // 13:40, lunch is due at 13:45
      });
      expect(summary.reasons.u1).toBe("Nothing due yet: next is lunch at 13:45; 1 small log under 100 kcal don't count as a meal");
    });

    describe('when the push does not go out', () => {
      const failingPush = (): PushSender => ({
        send: vi.fn(async (tokens) => ({ attempted: tokens.length, sent: 0, failed: tokens.length, invalidTokens: [], error: 'apns_503' })),
      });

      it('tries the same check-in again on the next run instead of going silent', async () => {
        const fake = makeFakePrisma([baseUser()], { seedFoods: true });
        fake.meal.create({ data: breakfast });
        await runScoreConfidenceJob({ prisma: fake as unknown as PrismaClient, push: failingPush(), voice, now: LUNCH_PLUS_50 });
        expect(fake.__tables.checkIns[0]).toMatchObject({ deliveryStatus: 'FAILED', lastPushError: 'apns_503' });
        fake.__tables.checkIns[0]!.createdAt = LUNCH_PLUS_50;

        const again = await runScoreConfidenceJob({
          prisma: fake as unknown as PrismaClient,
          push,
          voice,
          now: new Date(LUNCH_PLUS_50.getTime() + 15 * 60_000),
        });
        expect(again.checkInsRedelivered).toBe(1);
        expect(fake.__tables.checkIns).toHaveLength(1);
        expect(fake.__tables.checkIns[0]).toMatchObject({ deliveryStatus: 'SENT', lastPushError: null });
      });

      it('lets go of a check-in that never reached the phone, without counting a miss, so a new one can follow', async () => {
        const fake = makeFakePrisma([baseUser()], { seedFoods: true });
        fake.meal.create({ data: breakfast });
        await runScoreConfidenceJob({ prisma: fake as unknown as PrismaClient, push: failingPush(), voice, now: LUNCH_PLUS_50 });
        const later = new Date(LUNCH_PLUS_50.getTime() + (DELIVERY_RETRY_WINDOW_MIN + 5) * 60_000);
        fake.__tables.checkIns[0]!.createdAt = LUNCH_PLUS_50;

        const summary = await runScoreConfidenceJob({ prisma: fake as unknown as PrismaClient, push, voice, now: later });

        expect(fake.__tables.checkIns[0]).toMatchObject({ status: 'EXPIRED' });
        expect(summary.misses).toBe(0);
        expect(fake.__tables.escalationStates[0]?.consecutiveMisses ?? 0).toBe(0);
      });
    });

    it('holds a due lunch while the day is on pace, in one audit row, then fires once it runs long', async () => {
      const fake = makeFakePrisma([baseUser()], { seedFoods: true });
      fake.meal.create({ data: { ...breakfast, kcal: 1500 } });
      const run = (now: Date) =>
        runScoreConfidenceJob({ prisma: fake as unknown as PrismaClient, push, voice, now });

      const first = await run(LUNCH_PLUS_50);
      expect(first.checkInsCreated).toBe(0);
      expect(first.skipped.below_threshold).toBe(1);
      await run(new Date('2026-07-01T18:20:00Z')); // 14:20, still held
      expect(fake.__tables.confidenceScores).toHaveLength(1);
      expect(fake.__tables.confidenceScores[0]).toMatchObject({ firedCheckIn: false, episodeKey: '2026-07-01:lunch' });

      const late = await run(new Date('2026-07-01T19:20:00Z')); // 15:20 — 95 min past due
      expect(late.checkInsCreated).toBe(1);
      expect(fake.__tables.confidenceScores).toHaveLength(1);
      expect(fake.__tables.confidenceScores[0]).toMatchObject({ firedCheckIn: true });
      expect(fake.__tables.checkIns[0]).toMatchObject({ slot: 'lunch', confidenceScoreId: fake.__tables.confidenceScores[0]!.id });
    });

    it('does not check in twice for the same meal', async () => {
      const fake = makeFakePrisma([baseUser()]);
      fake.meal.create({ data: breakfast });
      fake.__tables.checkIns.push({
        id: 'ci_lunch',
        userId: 'u1',
        status: 'LOGGED',
        tier: 1,
        createdAt: new Date('2026-07-01T17:46:00Z'), // 13:46 — this morning's lunch check-in
      });

      const summary = await runScoreConfidenceJob({
        prisma: fake as unknown as PrismaClient,
        push,
        voice,
        now: new Date('2026-07-01T19:00:00Z'), // 15:00
      });

      expect(summary.checkInsCreated).toBe(0);
    });

    it('stays quiet once the day’s target is met', async () => {
      const fake = makeFakePrisma([baseUser()]);
      fake.meal.create({ data: { ...breakfast, kcal: 2300 } });

      const summary = await runScoreConfidenceJob({
        prisma: fake as unknown as PrismaClient,
        push,
        voice,
        now: new Date('2026-07-01T23:50:00Z'), // 19:50 — dinner is due, but the day is covered
      });

      expect(summary.checkInsCreated).toBe(0);
    });
  });
  describe('closing the daily gap', () => {
    const at = (iso: string, kcal: number) => ({ userId: 'u1', loggedAt: new Date(iso), kcal, proteinG: 20, source: 'TEXT' });
    const breakfast = at('2026-07-01T12:10:00Z', 500); // 08:10 New York

    it('follows up a light lunch with a top-up check-in', async () => {
      const fake = makeFakePrisma([baseUser()], { seedFoods: true });
      fake.meal.create({ data: breakfast });
      fake.meal.create({ data: at('2026-07-01T17:05:00Z', 200) }); // 13:05, a 200 kcal lunch

      const summary = await runScoreConfidenceJob({
        prisma: fake as unknown as PrismaClient,
        push,
        voice,
        now: new Date('2026-07-01T18:20:00Z'), // 14:20
      });

      expect(summary.checkInsCreated).toBe(1);
      expect(fake.__tables.checkIns[0]).toMatchObject({ kind: 'TOP_UP', slot: 'lunch' });
      expect(fake.__tables.checkIns[0]!.message).toMatch(/^Lunch was light\. Add .+ to stay on pace\.$/);
    });

    it('leaves a real lunch alone', async () => {
      const fake = makeFakePrisma([baseUser()], { seedFoods: true });
      fake.meal.create({ data: breakfast });
      fake.meal.create({ data: at('2026-07-01T17:05:00Z', 700) });

      const summary = await runScoreConfidenceJob({
        prisma: fake as unknown as PrismaClient,
        push,
        voice,
        now: new Date('2026-07-01T18:20:00Z'),
      });

      expect(summary.checkInsCreated).toBe(0);
    });

    it('closes the day in the evening when it is still well short', async () => {
      const fake = makeFakePrisma([baseUser()], { seedFoods: true });
      fake.meal.create({ data: breakfast });
      fake.meal.create({ data: at('2026-07-01T17:05:00Z', 600) });
      fake.meal.create({ data: at('2026-07-01T23:10:00Z', 600) }); // 19:10 dinner; day at 1,700 of 2,200

      const early = await runScoreConfidenceJob({
        prisma: fake as unknown as PrismaClient,
        push,
        voice,
        now: new Date('2026-07-02T00:20:00Z'), // 20:20 — the close comes at 20:30
      });
      expect(early.checkInsCreated).toBe(0);

      const summary = await runScoreConfidenceJob({
        prisma: fake as unknown as PrismaClient,
        push,
        voice,
        now: new Date('2026-07-02T00:35:00Z'), // 20:35
      });
      expect(summary.checkInsCreated).toBe(1);
      expect(fake.__tables.checkIns[0]).toMatchObject({ kind: 'CLOSE', slot: 'close', episodeKey: '2026-07-01:close' });
      expect(fake.__tables.checkIns[0]!.message).toMatch(/^You're 500 kcal short today\./);
      expect(fake.__tables.prescriptions).toHaveLength(1);
    });

    it('lets an unanswered close lapse without counting a miss', async () => {
      const fake = makeFakePrisma([baseUser()]);
      fake.__tables.checkIns.push({
        id: 'ci_close',
        userId: 'u1',
        kind: 'CLOSE',
        slot: 'close',
        status: 'PENDING',
        tier: 1,
        deferCount: 0,
        deliveryStatus: 'SENT',
        createdAt: hoursAgo(5),
        deliveredAt: hoursAgo(5),
      });

      const summary = await runScoreConfidenceJob({ prisma: fake as unknown as PrismaClient, push, voice, now: NOW });

      expect(summary.misses).toBe(0);
      expect(fake.__tables.checkIns.find((c) => c.id === 'ci_close')).toMatchObject({ status: 'EXPIRED' });
    });

    it('stops after the daily check-in budget is spent', async () => {
      const fake = makeFakePrisma([baseUser()], { seedFoods: true });
      for (let i = 0; i < 4; i += 1) {
        fake.__tables.checkIns.push({
          id: `ci_${i}`,
          userId: 'u1',
          status: 'LOGGED',
          tier: 1,
          kind: 'MEAL',
          createdAt: new Date('2026-07-01T12:30:00Z'),
        });
      }

      const summary = await runScoreConfidenceJob({ prisma: fake as unknown as PrismaClient, push, voice, now: NOW });

      expect(summary.checkInsCreated).toBe(0);
      expect(summary.skipped.daily_cap).toBe(1);
    });
  });
});
