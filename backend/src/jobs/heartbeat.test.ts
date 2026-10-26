import { describe, expect, it } from 'vitest';
import { MIN_GAP_MS, ranTooRecently } from './heartbeat.js';

describe('ranTooRecently', () => {
  const now = Date.parse('2026-10-26T12:00:00Z');
  it('skips a call right after a run', () => {
    expect(ranTooRecently(new Date(now - 30_000), now)).toBe(true);
    expect(ranTooRecently(new Date(now - MIN_GAP_MS + 1), now)).toBe(true);
  });
  it('lets a later call through', () => {
    expect(ranTooRecently(new Date(now - MIN_GAP_MS), now)).toBe(false);
    expect(ranTooRecently(new Date(now - 15 * 60_000), now)).toBe(false);
  });
  it('runs when it never has', () => {
    expect(ranTooRecently(null, now)).toBe(false);
    expect(ranTooRecently(undefined, now)).toBe(false);
  });
});
