import type { PrismaClient } from '@prisma/client';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { STAPLE_FOODS } from '../data/stapleFoods.js';
import type { ManagerVoice } from '../managerVoice/types.js';
import type { PushPayload, PushSender } from '../push/types.js';
import { runScoreConfidenceJob } from './scoreConfidence.js';

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
  const pushTokens: AnyRow[] = [];
  const foodItems: AnyRow[] = [];
  const dietaryRestrictions: AnyRow[] = [];
  const prescriptions: AnyRow[] = [];
  let seq = 0;
  const id = (p: string) => `${p}_${(seq += 1)}`;

  if (opts.seedFoods) {
    for (const f of STAPLE_FOODS) foodItems.push({ id: id('fi'), isStaple: true, ...f });
  }

  const match = (row: AnyRow, where: AnyRow = {}): boolean =>
    Object.entries(where).every(([k, v]) => {
      if (v && typeof v === 'object') {
        const cond = v as Record<string, unknown>;
        if ('in' in cond) return (cond.in as unknown[]).includes(row[k]);
        if ('gte' in cond) return (row[k] as Date) >= (cond.gte as Date);
        if ('not' in cond) return row[k] !== cond.not;
      }
      return row[k] === v;
    });

  const collection = (rows: AnyRow[], prefix: string) => ({
    findMany: async ({ where }: { where?: AnyRow } = {}) => rows.filter((r) => match(r, where)),
    findFirst: async ({ where }: { where?: AnyRow } = {}) => rows.find((r) => match(r, where)) ?? null,
    create: async ({ data }: { data: AnyRow }) => {
      const row = { id: id(prefix), createdAt: NOW, updatedAt: NOW, deferCount: 0, ...data };
      rows.push(row);
      return row;
    },
    update: async ({ where, data }: { where: AnyRow; data: AnyRow }) => {
      const row = rows.find((r) => match(r, where));
      if (row) Object.assign(row, data);
      return row;
    },
    upsert: async ({ where, create, update }: { where: AnyRow; create: AnyRow; update: AnyRow }) => {
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
    },
    user: {
      findMany: async () => users.filter((u) => u.onboarding != null),
    },
    checkIn: collection(checkIns, 'ci'),
    confidenceScore: collection(confidenceScores, 'cs'),
    escalationState: collection(escalationStates, 'es'),
    escalationConversation: collection(escalationConversations, 'ec'),
    meal: collection(meals, 'm'),
    pushToken: collection(pushTokens, 'pt'),
    foodItem: collection(foodItems, 'fi'),
    dietaryRestriction: collection(dietaryRestrictions, 'dr'),
    prescription: collection(prescriptions, 'rx'),
  };
}

function baseUser(over: AnyRow = {}): AnyRow {
  return {
    id: 'u1',
    timezone: 'America/New_York',
    createdAt: hoursAgo(1000),
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
    },
    safetyScreening: { enforcementEnabled: true },
    escalationState: { consecutiveMisses: 0, currentTier: 1, checkInsPaused: false, backedOffUntil: null },
    biosignalState: null,
    ...over,
  };
}

const sentPushes: PushPayload[] = [];
const push: PushSender = { send: vi.fn(async (_tokens, payload) => void sentPushes.push(payload)) };
const voice: ManagerVoice = {
  checkInMessage: vi.fn(async () => 'Time to eat.'),
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
    expect(fake.__tables.confidenceScores[0]).toMatchObject({ firedCheckIn: false });
  });
});
