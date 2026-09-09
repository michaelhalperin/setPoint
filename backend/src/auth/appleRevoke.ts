import jwt from 'jsonwebtoken';
import { env } from '../env.js';

const APPLE_REVOKE_URL = 'https://appleid.apple.com/auth/revoke';
const APPLE_AUD = 'https://appleid.apple.com';

/** The short-lived client secret Apple's token endpoints require (ES256 JWT). */
export function buildAppleClientSecret(): string | null {
  if (!env.APPLE_TEAM_ID || !env.APPLE_KEY_ID || !env.APPLE_PRIVATE_KEY || !env.APPLE_CLIENT_ID) {
    return null;
  }
  const now = Math.floor(Date.now() / 1000);
  return jwt.sign(
    { iss: env.APPLE_TEAM_ID, iat: now, exp: now + 300, aud: APPLE_AUD, sub: env.APPLE_CLIENT_ID },
    env.APPLE_PRIVATE_KEY.replace(/\\n/g, '\n'),
    { algorithm: 'ES256', keyid: env.APPLE_KEY_ID },
  );
}

export class AppleRevokeUnconfiguredError extends Error {}

/**
 * Revokes a Sign in with Apple refresh token (§4 — required by Apple when a user
 * deletes their account). Throws AppleRevokeUnconfiguredError if the SIWA key
 * material is not set; the caller treats that as a soft failure.
 */
export async function revokeAppleToken(refreshToken: string): Promise<void> {
  const clientSecret = buildAppleClientSecret();
  if (!clientSecret) throw new AppleRevokeUnconfiguredError('Sign in with Apple revocation is not configured');

  const res = await fetch(APPLE_REVOKE_URL, {
    method: 'POST',
    headers: { 'content-type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      client_id: env.APPLE_CLIENT_ID,
      client_secret: clientSecret,
      token: refreshToken,
      token_type_hint: 'refresh_token',
    }),
  });

  if (!res.ok) throw new Error(`Apple revoke failed (${res.status})`);
}
