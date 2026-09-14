import type { PrismaClient } from '@prisma/client';
import { describe, expect, it } from 'vitest';
import {
  appAccountTokenFor,
  isEntitled,
  subscriptionFromTransaction,
  SubscriptionVerificationError,
  SUBSCRIPTION_GRACE_MS,
  verifyTransaction,
  type VerifiedSubscription,
} from './entitlement.js';
import { saveVerifiedSubscription, SubscriptionOwnedElsewhereError } from './store.js';

function unsignedJws(payload: Record<string, unknown>, header: Record<string, unknown> = { alg: 'ES256' }): string {
  const enc = (o: Record<string, unknown>) => Buffer.from(JSON.stringify(o)).toString('base64url');
  return `${enc(header)}.${enc(payload)}.c2ln`;
}

const NOW = new Date('2026-09-14T12:00:00Z');
const DAY = 86_400_000;

describe('subscription entitlement', () => {
  it('is open when the gate is off', () => {
    expect(isEntitled({ subscriptionStatus: null, subscriptionExpiresAt: null }, NOW, false)).toBe(true);
  });

  it('honours expiry plus a 3-day grace', () => {
    const expired = new Date(NOW.getTime() - 2 * DAY);
    expect(isEntitled({ subscriptionStatus: 'EXPIRED', subscriptionExpiresAt: expired }, NOW, true)).toBe(true);
    const tooOld = new Date(NOW.getTime() - SUBSCRIPTION_GRACE_MS - 1000);
    expect(isEntitled({ subscriptionStatus: 'EXPIRED', subscriptionExpiresAt: tooOld }, NOW, true)).toBe(false);
  });

  it('never lets a stored ACTIVE status outlive the expiry', () => {
    const longGone = new Date(NOW.getTime() - 60 * DAY);
    expect(isEntitled({ subscriptionStatus: 'ACTIVE', subscriptionExpiresAt: longGone }, NOW, true)).toBe(false);
    expect(isEntitled({ subscriptionStatus: 'ACTIVE', subscriptionExpiresAt: null }, NOW, true)).toBe(false);
  });

  it('cuts a refunded subscription off immediately', () => {
    const future = new Date(NOW.getTime() + 300 * DAY);
    expect(isEntitled({ subscriptionStatus: 'REVOKED', subscriptionExpiresAt: future }, NOW, true)).toBe(false);
  });

  it('reads a verified transaction as a free trial', () => {
    const sub = subscriptionFromTransaction(
      {
        productId: 'setpoint.yearly',
        originalTransactionId: '2000001',
        expiresDate: NOW.getTime() + 7 * DAY,
        offerType: 1,
        offerDiscountType: 'FREE_TRIAL',
        environment: 'Sandbox',
      },
      NOW,
    );
    expect(sub).toMatchObject({ productId: 'setpoint.yearly', status: 'TRIALING', originalTransactionId: '2000001' });
  });

  it('marks a revoked transaction', () => {
    const sub = subscriptionFromTransaction(
      { productId: 'setpoint.monthly', originalTransactionId: '1', expiresDate: NOW.getTime() + DAY, revocationDate: NOW.getTime() },
      NOW,
    );
    expect(sub.status).toBe('REVOKED');
  });

  it('rejects a forged transaction that is not signed by Apple', async () => {
    for (const environment of ['Sandbox', 'Production', 'Nonsense']) {
      const forged = unsignedJws({
        productId: 'setpoint.yearly',
        originalTransactionId: '1',
        bundleId: 'com.setpoint.app',
        expiresDate: NOW.getTime() + 3650 * DAY,
        signedDate: NOW.getTime(),
        environment,
      });
      await expect(verifyTransaction(forged, NOW)).rejects.toBeInstanceOf(SubscriptionVerificationError);
    }
  });

  it('gives every user a stable, distinct UUID account token', () => {
    const a = appAccountTokenFor('user_a');
    expect(a).toMatch(/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/);
    expect(appAccountTokenFor('user_a')).toBe(a);
    expect(appAccountTokenFor('user_b')).not.toBe(a);
  });
});

describe('saveVerifiedSubscription', () => {
  type Row = {
    id: string;
    subscriptionStatus: string | null;
    subscriptionExpiresAt: Date | null;
    subscriptionProductId: string | null;
    subscriptionOriginalTransactionId: string | null;
  };
  const blank = (id: string): Row => ({
    id,
    subscriptionStatus: null,
    subscriptionExpiresAt: null,
    subscriptionProductId: null,
    subscriptionOriginalTransactionId: null,
  });
  function fakePrisma(rows: Row[]) {
    return {
      user: {
        findUnique: async ({ where }: { where: Partial<Row> }) =>
          rows.find((r) => Object.entries(where).every(([k, v]) => r[k as keyof Row] === v)) ?? null,
        update: async ({ where, data }: { where: { id: string }; data: Partial<Row> }) => {
          const row = rows.find((r) => r.id === where.id)!;
          Object.assign(row, data);
          return row;
        },
      },
    } as unknown as PrismaClient;
  }
  const sub = (over: Partial<VerifiedSubscription> = {}): VerifiedSubscription => ({
    status: 'ACTIVE',
    expiresAt: new Date(NOW.getTime() + 30 * DAY),
    productId: 'setpoint.monthly',
    originalTransactionId: 'otx_1',
    appAccountToken: null,
    environment: 'Sandbox',
    ...over,
  });

  it('refuses a subscription another account already owns', async () => {
    const owner = { ...blank('u_owner'), subscriptionOriginalTransactionId: 'otx_1' };
    const prisma = fakePrisma([owner, blank('u_other')]);
    await expect(saveVerifiedSubscription(prisma, 'u_other', sub(), NOW)).rejects.toBeInstanceOf(
      SubscriptionOwnedElsewhereError,
    );
  });

  it('refuses a purchase made with another account token', async () => {
    const prisma = fakePrisma([blank('u1')]);
    await expect(
      saveVerifiedSubscription(prisma, 'u1', sub({ appAccountToken: appAccountTokenFor('u2') }), NOW),
    ).rejects.toBeInstanceOf(SubscriptionOwnedElsewhereError);
  });

  it('does not roll a renewal back with an older transaction', async () => {
    const later = new Date(NOW.getTime() + 60 * DAY);
    const row = { ...blank('u1'), subscriptionOriginalTransactionId: 'otx_1', subscriptionExpiresAt: later, subscriptionStatus: 'ACTIVE' };
    const prisma = fakePrisma([row]);
    const view = await saveVerifiedSubscription(prisma, 'u1', sub({ appAccountToken: appAccountTokenFor('u1') }), NOW);
    expect(view.expiresAt).toBe(later.toISOString());
  });
});
