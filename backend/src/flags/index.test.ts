import { describe, expect, it } from 'vitest';
import { FLAGS, flagOn, resolveFlags } from './index.js';

const user = { id: 'u1', role: 'USER' as const, group: 'beta' };
const row = (over: Partial<{ enabled: boolean; groups: string[]; roles: ('USER' | 'TRAINER' | 'ADMIN')[]; userIds: string[] }>) => ({
  key: 'order_nearby',
  enabled: false,
  groups: [],
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

  it('turns on for a group, a role or a user', () => {
    expect(flagOn('order_nearby', user, row({ groups: ['beta'] }))).toBe(true);
    expect(flagOn('order_nearby', { ...user, group: null }, row({ groups: ['beta'] }))).toBe(false);
    expect(flagOn('order_nearby', { ...user, role: 'TRAINER' }, row({ roles: ['TRAINER'] }))).toBe(true);
    expect(flagOn('order_nearby', user, row({ userIds: ['u1'] }))).toBe(true);
    expect(flagOn('order_nearby', user, row({ userIds: ['u2'], roles: ['ADMIN'] }))).toBe(false);
  });

  it('resolves every declared flag', () => {
    expect(Object.keys(resolveFlags(user, []))).toEqual(Object.keys(FLAGS));
  });

  it('keeps in-app language off until an override turns it on', () => {
    expect(flagOn('app_language', user, undefined)).toBe(false);
    expect(flagOn('app_language', user, { ...row({ enabled: true }), key: 'app_language' })).toBe(true);
  });

  it('keeps the nutrition assistant off until an override turns it on', () => {
    expect(flagOn('nutrition_chat', user, undefined)).toBe(false);
    expect(flagOn('nutrition_chat', user, { ...row({ enabled: true }), key: 'nutrition_chat' })).toBe(true);
  });

  it('keeps SetPoint Pro off until an override turns it on', () => {
    expect(flagOn('paywall', user, undefined)).toBe(false);
    expect(flagOn('paywall', user, { ...row({ enabled: true }), key: 'paywall' })).toBe(true);
  });
});
