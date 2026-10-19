import { describe, expect, it } from 'vitest';
import { FLAGS, flagOn, resolveFlags } from './index.js';

const user = { id: 'u1', role: 'USER' as const, cohort: 'dvir-pilot' };
const row = (over: Partial<{ enabled: boolean; cohorts: string[]; roles: ('USER' | 'TRAINER' | 'ADMIN')[]; userIds: string[] }>) => ({
  key: 'order_nearby',
  enabled: false,
  cohorts: [],
  roles: [],
  userIds: [],
  ...over,
});

describe('feature flags', () => {
  it('uses the default in code when there is no override', () => {
    expect(flagOn('order_nearby', user, undefined)).toBe(FLAGS.order_nearby.default);
  });

  it('is on for everyone when enabled', () => {
    expect(flagOn('order_nearby', user, row({ enabled: true }))).toBe(true);
  });

  it('is off for everyone with an empty override', () => {
    expect(flagOn('order_nearby', user, row({}))).toBe(false);
  });

  it('turns on for a cohort, a role or a user', () => {
    expect(flagOn('order_nearby', user, row({ cohorts: ['dvir-pilot'] }))).toBe(true);
    expect(flagOn('order_nearby', { ...user, cohort: null }, row({ cohorts: ['dvir-pilot'] }))).toBe(false);
    expect(flagOn('order_nearby', { ...user, role: 'TRAINER' }, row({ roles: ['TRAINER'] }))).toBe(true);
    expect(flagOn('order_nearby', user, row({ userIds: ['u1'] }))).toBe(true);
    expect(flagOn('order_nearby', user, row({ userIds: ['u2'], roles: ['ADMIN'] }))).toBe(false);
  });

  it('resolves every declared flag', () => {
    expect(Object.keys(resolveFlags(user, []))).toEqual(Object.keys(FLAGS));
  });
});
