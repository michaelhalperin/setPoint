import jwt from 'jsonwebtoken';
import { env } from '../env.js';

const TTL_SECONDS = 60 * 60 * 24 * 60; // 60 days

/**
 * Sliding renewal: once a token is this old, the next authenticated request
 * gets a fresh one back in `SESSION_RENEWAL_HEADER`. Anyone who opens the app
 * at least every ~7 weeks never hits the 60-day expiry.
 */
export const RENEW_AFTER_SECONDS = 60 * 60 * 24 * 7; // 7 days
export const SESSION_RENEWAL_HEADER = 'x-session-token';

/** Mints a SetPoint session JWT for a user id. */
export function issueSessionToken(userId: string): string {
  return jwt.sign({ sub: userId }, env.JWT_SECRET, { algorithm: 'HS256', expiresIn: TTL_SECONDS });
}

export class SessionTokenError extends Error {}

/** Verifies a session JWT and returns the user id, or throws SessionTokenError. */
export function verifySessionToken(token: string): { userId: string; issuedAt: Date | null } {
  let payload: jwt.JwtPayload | string;
  try {
    payload = jwt.verify(token, env.JWT_SECRET, { algorithms: ['HS256'] });
  } catch (err) {
    throw new SessionTokenError((err as Error).message);
  }
  if (typeof payload === 'string' || !payload.sub) {
    throw new SessionTokenError('token missing subject');
  }
  return {
    userId: payload.sub,
    issuedAt: typeof payload.iat === 'number' ? new Date(payload.iat * 1000) : null,
  };
}

/** Whether a verified token is old enough to be swapped for a fresh one. */
export function shouldRenewSession(issuedAt: Date | null, now: Date = new Date()): boolean {
  if (!issuedAt) return true;
  return now.getTime() - issuedAt.getTime() >= RENEW_AFTER_SECONDS * 1000;
}
