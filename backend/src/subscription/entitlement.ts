import { env } from '../env.js';

export const SUBSCRIPTION_GRACE_MS = 3 * 86_400_000;
export const YEARLY_PRODUCT = 'setpoint.yearly';
export const MONTHLY_PRODUCT = 'setpoint.monthly';

export type SubscriptionUser = {
  subscriptionStatus?: string | null;
  subscriptionExpiresAt?: Date | null;
};

export function subscriptionGateOn(): boolean {
  if (env.SUBSCRIPTION_GATE === 'true') return true;
  if (env.SUBSCRIPTION_GATE === 'false') return false;
  return env.NODE_ENV === 'production';
}

/** True when check-ins, calendar, training and appetite may run. */
export function isEntitled(user: SubscriptionUser, now = new Date(), gate = subscriptionGateOn()): boolean {
  if (!gate) return true;
  const expires = user.subscriptionExpiresAt?.getTime() ?? null;
  if (expires != null && expires + SUBSCRIPTION_GRACE_MS >= now.getTime()) return true;
  const status = user.subscriptionStatus;
  return status === 'ACTIVE' || status === 'TRIALING' || status === 'GRACE';
}

export function decodeJwsPayload(jws: string): Record<string, unknown> {
  const parts = jws.split('.');
  if (parts.length < 2) throw new Error('invalid jws');
  const json = Buffer.from(parts[1]!, 'base64url').toString('utf8');
  const payload = JSON.parse(json) as unknown;
  if (!payload || typeof payload !== 'object') throw new Error('invalid jws payload');
  return payload as Record<string, unknown>;
}

export function subscriptionFromJws(
  jws: string,
  now = new Date(),
): { status: 'ACTIVE' | 'TRIALING' | 'EXPIRED'; expiresAt: Date; productId: string } {
  const payload = decodeJwsPayload(jws);
  const productId = String(payload.productId ?? '');
  if (productId !== YEARLY_PRODUCT && productId !== MONTHLY_PRODUCT) {
    throw new Error('unknown product');
  }
  const rawExpires = payload.expiresDate;
  const expiresMs = typeof rawExpires === 'number' ? rawExpires : Number(rawExpires);
  if (!Number.isFinite(expiresMs)) throw new Error('missing expiresDate');
  const expiresAt = new Date(expiresMs);
  const intro =
    payload.offerDiscountType === 'FREE_TRIAL' ||
    payload.offerType === 1 ||
    payload.inIntroOfferPeriod === true;
  let status: 'ACTIVE' | 'TRIALING' | 'EXPIRED' = expiresAt.getTime() >= now.getTime() ? 'ACTIVE' : 'EXPIRED';
  if (status === 'ACTIVE' && intro) status = 'TRIALING';
  return { status, expiresAt, productId };
}
