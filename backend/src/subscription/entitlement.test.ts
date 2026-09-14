import { describe, expect, it } from 'vitest';
import {
  isEntitled,
  subscriptionFromJws,
  SUBSCRIPTION_GRACE_MS,
} from './entitlement.js';

function jws(payload: Record<string, unknown>): string {
  const body = Buffer.from(JSON.stringify(payload)).toString('base64url');
  return `eyJhbGciOiJub25lIn0.${body}.sig`;
}

const NOW = new Date('2026-09-14T12:00:00Z');

describe('subscription entitlement', () => {
  it('is open when the gate is off', () => {
    expect(isEntitled({ subscriptionStatus: null, subscriptionExpiresAt: null }, NOW, false)).toBe(true);
  });

  it('honours expiry plus a 3-day grace', () => {
    const expired = new Date(NOW.getTime() - 2 * 86_400_000);
    expect(isEntitled({ subscriptionStatus: 'EXPIRED', subscriptionExpiresAt: expired }, NOW, true)).toBe(true);
    const tooOld = new Date(NOW.getTime() - SUBSCRIPTION_GRACE_MS - 1000);
    expect(isEntitled({ subscriptionStatus: 'EXPIRED', subscriptionExpiresAt: tooOld }, NOW, true)).toBe(false);
  });

  it('treats ACTIVE and TRIALING as entitled', () => {
    expect(isEntitled({ subscriptionStatus: 'ACTIVE', subscriptionExpiresAt: null }, NOW, true)).toBe(true);
    expect(isEntitled({ subscriptionStatus: 'NONE', subscriptionExpiresAt: null }, NOW, true)).toBe(false);
  });

  it('reads a StoreKit JWS payload', () => {
    const token = jws({
      productId: 'setpoint.yearly',
      expiresDate: NOW.getTime() + 7 * 86_400_000,
      offerType: 1,
    });
    const sub = subscriptionFromJws(token, NOW);
    expect(sub.productId).toBe('setpoint.yearly');
    expect(sub.status).toBe('TRIALING');
  });
});
