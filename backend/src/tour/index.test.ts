import type { PrismaClient } from '@prisma/client';
import { describe, expect, it } from 'vitest';
import { DEFAULT_TOUR, TOUR_ANCHORS, anchorsForAdmin, forApp, loadTour, tourProblems, tourSchema } from './index.js';

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
    expect(await loadTour(fakePrisma(saved))).toEqual(tourSchema.parse(saved));
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

describe('tip position', () => {
  it('starts automatic and unnudged, also for a tour saved before these fields existed', () => {
    for (const step of DEFAULT_TOUR.steps) {
      expect(step.side).toBe('auto');
      expect([step.dx, step.dy]).toEqual([0, 0]);
    }
    const old = tourSchema.parse({ revision: 1, steps: [{ id: 'a', anchor: 'today.orb', title: 'Hi', body: 'There' }] });
    expect(old.steps[0]).toMatchObject({ side: 'auto', dx: 0, dy: 0 });
  });

  it('keeps the owner\u2019s choice and passes it to the app', () => {
    const tour = tourSchema.parse({ revision: 2, steps: [{ id: 'a', anchor: 'today.orb', side: 'above', dx: 24, dy: -12, title: 'Hi', body: 'There' }] });
    expect(forApp(tour).steps[0]).toMatchObject({ side: 'above', dx: 24, dy: -12 });
    expect(tourSchema.safeParse({ revision: 1, steps: [{ id: 'a', anchor: null, side: 'left', title: 'x', body: 'y' }] }).success).toBe(false);
  });
});

describe('anchorsForAdmin', () => {
  it('knows where every element sits on the phone', () => {
    for (const a of anchorsForAdmin()) {
      expect(a.frame, a.id).not.toBeNull();
      expect(a.frame![2]).toBeGreaterThan(10);
    }
  });
});

describe('forApp', () => {
  it('adds the spotlight shape of each step\u2019s element', () => {
    const out = forApp(DEFAULT_TOUR);
    const orb = out.steps.find((s) => s.anchor === 'today.orb')!;
    expect(orb.pad).toBe(8);
    expect(orb.radius).toBe(150);
    expect(out.steps[0]!.pad).toBeNull();
  });
});
