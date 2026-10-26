import type { PrismaClient } from '@prisma/client';
import { describe, expect, it } from 'vitest';
import { DEFAULT_TOUR, TOUR_ANCHORS, loadTour, tourProblems, tourSchema } from './index.js';

const fakePrisma = (value: unknown | undefined) =>
  ({ appConfig: { findUnique: async () => (value === undefined ? null : { key: 'tour', value }) } }) as unknown as PrismaClient;

describe('the built-in tour', () => {
  it('is valid and every step points at a real element', () => {
    expect(tourSchema.safeParse(DEFAULT_TOUR).success).toBe(true);
    expect(tourProblems(DEFAULT_TOUR)).toBeNull();
    const ids = new Set<string>(TOUR_ANCHORS.map((a) => a.id));
    for (const step of DEFAULT_TOUR.steps) if (step.anchor) expect(ids.has(step.anchor)).toBe(true);
  });

  it('has a Hebrew line for every step', () => {
    for (const step of DEFAULT_TOUR.steps) expect(step.he?.title && step.he.body).toBeTruthy();
  });

  it('names each element once', () => {
    const ids = TOUR_ANCHORS.map((a) => a.id);
    expect(new Set(ids).size).toBe(ids.length);
  });
});

describe('loadTour', () => {
  it('falls back to the built-in tour when nothing is saved', async () => {
    expect(await loadTour(fakePrisma(undefined))).toEqual(DEFAULT_TOUR);
  });

  it('returns what the owner saved', async () => {
    const saved = { revision: 3, steps: [{ id: 'a', anchor: 'today.orb', welcome: false, title: 'Hi', body: 'There', he: null }] };
    expect(await loadTour(fakePrisma(saved))).toEqual(saved);
  });

  it('falls back when a saved element no longer exists', async () => {
    const stale = { revision: 2, steps: [{ id: 'a', anchor: 'gone.element', title: 'Hi', body: 'There' }] };
    expect(await loadTour(fakePrisma(stale))).toEqual(DEFAULT_TOUR);
  });
});

describe('tourProblems', () => {
  const step = (over: object) => tourSchema.shape.steps.element.parse({ id: 'a', anchor: null, title: 't', body: 'b', ...over });

  it('allows one opening prompt, without an element', () => {
    expect(tourProblems({ revision: 1, steps: [step({ welcome: true }), step({ id: 'b', anchor: 'today.orb' })] })).toBeNull();
    expect(tourProblems({ revision: 1, steps: [step({ welcome: true }), step({ id: 'b', welcome: true })] })).toMatch(/one step/i);
    expect(tourProblems({ revision: 1, steps: [step({ welcome: true, anchor: 'today.orb' })] })).toMatch(/no element/i);
  });

  it('rejects two steps with the same id', () => {
    expect(tourProblems({ revision: 1, steps: [step({}), step({})] })).toMatch(/share an id/i);
  });
});
