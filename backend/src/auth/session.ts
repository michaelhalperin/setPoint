import jwt from 'jsonwebtoken';
import { env } from '../env.js';

const TTL_SECONDS = 60 * 60 * 24 * 60; // 60 days

/** Mints a SetPoint session JWT for a user id. */
export function issueSessionToken(userId: string): string {
  return jwt.sign({ sub: userId }, env.JWT_SECRET, { algorithm: 'HS256', expiresIn: TTL_SECONDS });
}

export class SessionTokenError extends Error {}

/** Verifies a session JWT and returns the user id, or throws SessionTokenError. */
export function verifySessionToken(token: string): { userId: string } {
  let payload: jwt.JwtPayload | string;
  try {
    payload = jwt.verify(token, env.JWT_SECRET, { algorithms: ['HS256'] });
  } catch (err) {
    throw new SessionTokenError((err as Error).message);
  }
  if (typeof payload === 'string' || !payload.sub) {
    throw new SessionTokenError('token missing subject');
  }
  return { userId: payload.sub };
}
