import { env } from '../env.js';
import { buildAppleClientSecret } from './appleRevoke.js';

const APPLE_TOKEN_URL = 'https://appleid.apple.com/auth/token';

export type AppleTokenSet = {
  refreshToken: string | null;
  accessToken: string | null;
};

/**
 * Exchanges a Sign in with Apple authorization code for tokens so account
 * deletion can later call /auth/revoke. Soft-fails when Apple isn't configured.
 */
export async function exchangeAppleAuthorizationCode(code: string): Promise<AppleTokenSet> {
  const clientSecret = buildAppleClientSecret();
  if (!clientSecret || !env.APPLE_CLIENT_ID) return { refreshToken: null, accessToken: null };

  const res = await fetch(APPLE_TOKEN_URL, {
    method: 'POST',
    headers: { 'content-type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      client_id: env.APPLE_CLIENT_ID,
      client_secret: clientSecret,
      code,
      grant_type: 'authorization_code',
    }),
  });
  if (!res.ok) throw new Error(`Apple token exchange failed (${res.status})`);
  const body = (await res.json()) as { refresh_token?: string; access_token?: string };
  return {
    refreshToken: body.refresh_token ?? null,
    accessToken: body.access_token ?? null,
  };
}
