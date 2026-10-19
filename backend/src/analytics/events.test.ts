import { describe, expect, it } from 'vitest';
import { cleanProps, summarizeEvents, type EventRow } from './events.js';

describe('analytics props', () => {
  it('keeps short codes and drops free text', () => {
    expect(cleanProps({ source: 'TEXT', count: 2, ok: true })).toEqual({ source: 'TEXT', count: 2, ok: true });
    expect(cleanProps({ note: 'two eggs, toast and a latte' })).toBeUndefined();
    expect(cleanProps({ source: 'x'.repeat(41) })).toBeUndefined();
    expect(cleanProps({ 'bad key': 'A', nested: { a: 1 } })).toBeUndefined();
    expect(cleanProps('TEXT')).toBeUndefined();
  });
});

describe('summarizeEvents', () => {
  const at = (d: string) => new Date(`${d}T10:00:00Z`);
  const rows: EventRow[] = [
    { userId: 'a', name: 'signed_up', props: null, occurredAt: at('2026-10-10') },
    { userId: 'b', name: 'signed_up', props: null, occurredAt: at('2026-10-10') },
    { userId: 'a', name: 'onboarding_completed', props: null, occurredAt: at('2026-10-10') },
    { userId: 'a', name: 'meal_logged', props: { source: 'TEXT' }, occurredAt: at('2026-10-11') },
    { userId: 'a', name: 'meal_logged', props: { source: 'SAVED' }, occurredAt: at('2026-10-11') },
    { userId: 'a', name: 'check_in_answered', props: { answer: 'ate' }, occurredAt: at('2026-10-11') },
    { userId: 'a', name: 'day_settled', props: { kind: 'ON_TRACK' }, occurredAt: at('2026-10-12') },
    { userId: 'b', name: 'day_settled', props: { kind: 'UNDER' }, occurredAt: at('2026-10-12') },
    { userId: 'c', name: 'meal_logged', props: { source: 'TEXT' }, occurredAt: at('2026-10-12') },
    { userId: 'a', name: 'screen_viewed', props: { screen: 'today' }, occurredAt: at('2026-10-12') },
    { userId: 'a', name: 'screen_viewed', props: { screen: 'today' }, occurredAt: at('2026-10-12') },
    { userId: 'b', name: 'screen_viewed', props: { screen: 'train' }, occurredAt: at('2026-10-12') },
  ];
  const summary = summarizeEvents(rows);

  it('counts events and people per event', () => {
    expect(summary.totals.meal_logged).toEqual({ events: 3, users: 2 });
    expect(summary.totals.signed_up).toEqual({ events: 2, users: 2 });
  });

  it('builds the funnel from people who signed up in the range', () => {
    expect(summary.funnel).toEqual({ signedUp: 2, onboarded: 1, loggedAMeal: 1, answeredACheckIn: 1, hadAFullDay: 1 });
  });

  it('counts fully eaten days among settled ones', () => {
    expect(summary.days).toEqual({ settled: 2, fullyEaten: 1, fullyEatenRate: 0.5 });
  });

  it('gives people and actions per day, not counting the nightly settle as activity', () => {
    expect(summary.daily).toEqual([
      { date: '2026-10-10', activeUsers: 2, mealsLogged: 0, checkInsAnswered: 0 },
      { date: '2026-10-11', activeUsers: 1, mealsLogged: 2, checkInsAnswered: 1 },
      { date: '2026-10-12', activeUsers: 3, mealsLogged: 1, checkInsAnswered: 0 },
    ]);
  });

  it('counts views and people per screen', () => {
    expect(summary.screens).toEqual([
      { screen: 'today', views: 2, users: 1 },
      { screen: 'train', views: 1, users: 1 },
    ]);
  });
});
