import { describe, expect, it } from 'vitest';
import { buildPipeline, failureLabel, groupOf, levelOf, nameOf, outcomeOf, pushStatus, runsFrom, streakOf, type Level } from './ops.js';

describe('levelOf', () => {
  it('buckets how much of the target a day reached', () => {
    expect(levelOf(0, 2500)).toBe(0);
    expect(levelOf(500, 2500)).toBe(1);
    expect(levelOf(1000, 2500)).toBe(2);
    expect(levelOf(2000, 2500)).toBe(3);
    expect(levelOf(2400, 2500)).toBe(4);
    expect(levelOf(900, 0)).toBe(0);
  });
});

describe('streakOf', () => {
  it('counts days that reached most of the target, ending today or yesterday', () => {
    const l = (s: string): Level[] => s.split('').map((c) => (c === 'x' ? -1 : (Number(c) as Level)));
    expect(streakOf(l('1244344'))).toBe(5);
    expect(streakOf(l('4444441'))).toBe(6); // today still in progress
    expect(streakOf(l('44443'))).toBe(5);
    expect(streakOf(l('4440000'))).toBe(0);
    expect(streakOf([])).toBe(0);
  });
});

describe('pushStatus', () => {
  it('tells production from sandbox from nothing', () => {
    expect(pushStatus([{ environment: 'production' }, { environment: 'sandbox' }], true).kind).toBe('production');
    expect(pushStatus([{ environment: 'sandbox' }], true).kind).toBe('sandbox');
    expect(pushStatus([], true)).toMatchObject({ kind: 'none', tone: 'bad' });
    expect(pushStatus([], false).kind).toBe('setup');
  });
});

describe('check-in outcomes and groups', () => {
  const base = { tier: 1, kind: 'MEAL', status: 'PENDING', deliveryStatus: 'SENT' };
  it('maps delivery and status to one outcome', () => {
    expect(outcomeOf({ ...base, deliveryStatus: 'FAILED' })).toBe('failed');
    expect(outcomeOf({ ...base, status: 'LOGGED' })).toBe('ate');
    expect(outcomeOf({ ...base, deliveryStatus: 'OPENED' })).toBe('answered');
    expect(outcomeOf({ ...base, status: 'EXPIRED' })).toBe('ignored');
  });
  it('groups by the kinds shown on the Delivery screen', () => {
    expect(groupOf({ tier: 3, kind: 'MEAL' }).key).toBe('talk');
    expect(groupOf({ tier: 1, kind: 'REFUEL' }).key).toBe('refuel');
    expect(groupOf({ tier: 2, kind: 'MEAL' }).key).toBe('firm');
    expect(groupOf({ tier: 1, kind: 'MEAL' }).key).toBe('first');
    expect(groupOf({ tier: 1, kind: 'TOP_UP' }).key).toBe('close');
  });
  it('names the reason a push failed', () => {
    expect(failureLabel('no_push_token')).toBe('No push token');
    expect(failureLabel('apns_not_configured')).toBe('Server has no push key');
    expect(failureLabel('apns_error: bad key')).toBe('Server key problem');
    expect(failureLabel('BadDeviceToken')).toBe('Apple rejected it');
  });
});

describe('buildPipeline', () => {
  const now = new Date();
  it('breaks at step 1 with no token', () => {
    const { steps, why } = buildPipeline({ tokens: [], apnsConfigured: true, recent: [] });
    expect(steps[0]!.state).toBe('no');
    expect(why).toMatch(/No token/);
  });
  it('breaks at step 2 for a sandbox-only token', () => {
    const { steps } = buildPipeline({ tokens: [{ environment: 'sandbox', lastSeenAt: now }], apnsConfigured: true, recent: [] });
    expect(steps.map((s) => s.state).slice(0, 2)).toEqual(['ok', 'no']);
  });
  it('flags a server without its push key', () => {
    const { steps, why } = buildPipeline({ tokens: [{ environment: 'production', lastSeenAt: now }], apnsConfigured: false, recent: [] });
    expect(steps[2]!.state).toBe('no');
    expect(why).toMatch(/no push key/);
  });
  it('is all fine for a production token and an accepted push', () => {
    const { steps, why } = buildPipeline({
      tokens: [{ environment: 'production', lastSeenAt: now }],
      apnsConfigured: true,
      recent: [{ deliveryStatus: 'ANSWERED', status: 'LOGGED', lastPushError: null }],
    });
    expect(steps.every((s) => s.state === 'ok')).toBe(true);
    expect(why).toBeNull();
  });
});

describe('small helpers', () => {
  it('names a person without leaking a long relay address', () => {
    expect(nameOf({ displayName: ' Dana ', email: 'x@y.z' })).toBe('Dana');
    expect(nameOf({ displayName: null, email: 'sk7wd7yk89abcdefg@privaterelay.appleid.com' })).toBe('sk7wd7yk89abcd');
    expect(nameOf({ displayName: null, email: null })).toBe('Someone');
  });
  it('reads kept run times off the heartbeat summary', () => {
    expect(runsFrom({ runs: [1, 2, 'x'] })).toEqual([1, 2]);
    expect(runsFrom(null)).toEqual([]);
    expect(runsFrom({ error: 'x' })).toEqual([]);
  });
});
