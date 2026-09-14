import { createHash } from 'node:crypto';
import {
  Environment,
  OfferDiscountType,
  OfferType,
  SignedDataVerifier,
  type JWSTransactionDecodedPayload,
  type ResponseBodyV2DecodedPayload,
} from '@apple/app-store-server-library';
import { env, isProd } from '../env.js';
import { APPLE_ROOT_CA_G3_BASE64 } from './appleRoot.js';

export const SUBSCRIPTION_GRACE_MS = 3 * 86_400_000;
export const YEARLY_PRODUCT = 'setpoint.yearly';
export const MONTHLY_PRODUCT = 'setpoint.monthly';

export type SubscriptionStatus = 'ACTIVE' | 'TRIALING' | 'EXPIRED' | 'REVOKED';

export type SubscriptionUser = {
  subscriptionStatus?: string | null;
  subscriptionExpiresAt?: Date | null;
};

export class SubscriptionVerificationError extends Error {}

/** Off unless SUBSCRIPTION_GATE=true — turning it on cuts non-subscribers off from check-ins. */
export function subscriptionGateOn(): boolean {
  return env.SUBSCRIPTION_GATE === 'true';
}

/**
 * True when check-ins, calendar, training and appetite may run. Only the App Store
 * expiry decides — a stored status never outlives it — plus a short grace for
 * billing retries. A refunded or revoked subscription is never entitled.
 */
export function isEntitled(user: SubscriptionUser, now = new Date(), gate = subscriptionGateOn()): boolean {
  if (!gate) return true;
  if (user.subscriptionStatus === 'REVOKED') return false;
  const expires = user.subscriptionExpiresAt?.getTime();
  return expires != null && expires + SUBSCRIPTION_GRACE_MS >= now.getTime();
}

/**
 * A stable UUID per user, passed to StoreKit as `appAccountToken` so a purchase
 * is tied to the SetPoint account that made it.
 */
export function appAccountTokenFor(userId: string): string {
  const hex = createHash('sha256').update(`setpoint.appAccountToken:${userId}`).digest('hex');
  const variant = ((parseInt(hex[16]!, 16) & 0x3) | 0x8).toString(16);
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-4${hex.slice(13, 16)}-${variant}${hex.slice(17, 20)}-${hex.slice(20, 32)}`;
}

export type VerifiedSubscription = {
  status: SubscriptionStatus;
  expiresAt: Date;
  productId: string;
  originalTransactionId: string;
  appAccountToken: string | null;
  environment: string;
};

export function subscriptionFromTransaction(payload: JWSTransactionDecodedPayload, now = new Date()): VerifiedSubscription {
  const productId = payload.productId ?? '';
  if (productId !== YEARLY_PRODUCT && productId !== MONTHLY_PRODUCT) {
    throw new SubscriptionVerificationError('unknown product');
  }
  if (payload.expiresDate == null || !Number.isFinite(payload.expiresDate)) {
    throw new SubscriptionVerificationError('missing expiresDate');
  }
  if (!payload.originalTransactionId) {
    throw new SubscriptionVerificationError('missing originalTransactionId');
  }
  const expiresAt = new Date(payload.expiresDate);
  let status: SubscriptionStatus = expiresAt.getTime() >= now.getTime() ? 'ACTIVE' : 'EXPIRED';
  const freeTrial =
    payload.offerType === OfferType.INTRODUCTORY_OFFER && payload.offerDiscountType === OfferDiscountType.FREE_TRIAL;
  if (status === 'ACTIVE' && freeTrial) status = 'TRIALING';
  if (payload.revocationDate != null) status = 'REVOKED';
  return {
    status,
    expiresAt,
    productId,
    originalTransactionId: payload.originalTransactionId,
    appAccountToken: payload.appAccountToken ?? null,
    environment: String(payload.environment ?? ''),
  };
}

/** Reads a JWS payload without trusting it — only to choose which verifier to use. */
export function peekJwsPayload(jws: string): Record<string, unknown> {
  const parts = jws.split('.');
  if (parts.length !== 3) throw new SubscriptionVerificationError('invalid jws');
  try {
    const payload = JSON.parse(Buffer.from(parts[1]!, 'base64url').toString('utf8')) as unknown;
    if (!payload || typeof payload !== 'object') throw new Error('not an object');
    return payload as Record<string, unknown>;
  } catch {
    throw new SubscriptionVerificationError('invalid jws payload');
  }
}

const verifiers = new Map<string, SignedDataVerifier>();

function verifierFor(environment: string): SignedDataVerifier {
  const cached = verifiers.get(environment);
  if (cached) return cached;
  const roots = [Buffer.from(APPLE_ROOT_CA_G3_BASE64, 'base64')];
  let verifier: SignedDataVerifier;
  switch (environment) {
    case Environment.PRODUCTION: {
      const appAppleId = Number(env.APPLE_APP_APPLE_ID);
      if (!env.APPLE_APP_APPLE_ID || !Number.isInteger(appAppleId)) {
        throw new SubscriptionVerificationError('APPLE_APP_APPLE_ID is not configured');
      }
      verifier = new SignedDataVerifier(roots, true, Environment.PRODUCTION, env.APP_BUNDLE_ID, appAppleId);
      break;
    }
    case Environment.SANDBOX:
      // TestFlight and App Review purchase in the sandbox against the production server.
      verifier = new SignedDataVerifier(roots, true, Environment.SANDBOX, env.APP_BUNDLE_ID);
      break;
    case Environment.XCODE:
    case Environment.LOCAL_TESTING:
      // Xcode StoreKit testing signs locally; there is nothing to verify, so never accept it in production.
      if (isProd) throw new SubscriptionVerificationError('Xcode StoreKit transactions are not accepted in production');
      verifier = new SignedDataVerifier(roots, false, environment, env.APP_BUNDLE_ID);
      break;
    default:
      throw new SubscriptionVerificationError('unknown App Store environment');
  }
  verifiers.set(environment, verifier);
  return verifier;
}

/** Verifies an App Store transaction signed by Apple (signature, certificate chain, bundle id, environment). */
export async function verifyTransaction(jws: string, now = new Date()): Promise<VerifiedSubscription> {
  const environment = String(peekJwsPayload(jws).environment ?? '');
  let payload: JWSTransactionDecodedPayload;
  try {
    payload = await verifierFor(environment).verifyAndDecodeTransaction(jws);
  } catch (err) {
    if (err instanceof SubscriptionVerificationError) throw err;
    throw new SubscriptionVerificationError('App Store transaction failed verification');
  }
  return subscriptionFromTransaction(payload, now);
}

/** Verifies an App Store Server Notification V2 and the transaction inside it. */
export async function verifyNotification(
  signedPayload: string,
  now = new Date(),
): Promise<{ notification: ResponseBodyV2DecodedPayload; subscription: VerifiedSubscription | null }> {
  const peeked = peekJwsPayload(signedPayload) as { data?: { environment?: string }; summary?: { environment?: string } };
  const environment = String(peeked.data?.environment ?? peeked.summary?.environment ?? '');
  const verifier = verifierFor(environment);
  let notification: ResponseBodyV2DecodedPayload;
  try {
    notification = await verifier.verifyAndDecodeNotification(signedPayload);
  } catch (err) {
    if (err instanceof SubscriptionVerificationError) throw err;
    throw new SubscriptionVerificationError('App Store notification failed verification');
  }
  const signedTransaction = notification.data?.signedTransactionInfo;
  if (!signedTransaction) return { notification, subscription: null };
  return { notification, subscription: await verifyTransaction(signedTransaction, now) };
}
