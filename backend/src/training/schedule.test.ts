import { describe, expect, it } from 'vitest';
import { canEdit, followingStarts, startProblem } from './schedule.js';

const TZ = 'Asia/Jerusalem';
const now = new Date('2026-10-20T09:00:00Z'); // Tue 12:00 local

describe('startProblem', () => {
  it('allows a week back through 8 weeks ahead', () => {
    expect(startProblem(new Date('2026-10-14T06:00:00Z'), now, TZ)).toBeNull();
    expect(startProblem(new Date('2026-12-15T06:00:00Z'), now, TZ)).toBeNull();
  });

  it('refuses older than a week and past the horizon', () => {
    expect(startProblem(new Date('2026-10-12T06:00:00Z'), now, TZ)).toBe('more than a week ago');
    expect(startProblem(new Date('2026-12-17T06:00:00Z'), now, TZ)).toBe('more than 8 weeks ahead');
    expect(startProblem(new Date('nope'), now, TZ)).toBe('invalid start');
  });
});

describe('canEdit', () => {
  it('only planned sessions that have not started', () => {
    expect(canEdit({ source: 'PLANNED', start: new Date('2026-10-20T15:00:00Z') }, now)).toBe(true);
    expect(canEdit({ source: 'PLANNED', start: new Date('2026-10-20T08:00:00Z') }, now)).toBe(false);
    expect(canEdit({ source: 'HEALTHKIT', start: new Date('2026-10-21T08:00:00Z') }, now)).toBe(false);
  });
});

describe('followingStarts', () => {
  it('moves later sessions by the same days and to the new time', () => {
    // Thursdays 18:00 local → Fridays 07:00 local; clocks go back on 25 Oct.
    const rows = [
      { id: 'a', start: new Date('2026-10-22T15:00:00Z') }, // UTC+3
      { id: 'b', start: new Date('2026-10-29T16:00:00Z') }, // UTC+2
    ];
    const moved = followingStarts(rows, rows[0]!.start, new Date('2026-10-23T04:00:00Z'), TZ);
    expect(moved.get('a')!.toISOString()).toBe('2026-10-23T04:00:00.000Z');
    expect(moved.get('b')!.toISOString()).toBe('2026-10-30T05:00:00.000Z'); // still 07:00 local
  });
});
