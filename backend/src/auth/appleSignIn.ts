import { createPublicKey, type JsonWebKey } from 'node:crypto';
import jwt from 'jsonwebtoken';

const APPLE_ISSUER = 'https://appleid.apple.com';
const APPLE_JWKS_URL = 'https://appleid.apple.com/auth/keys';
const JWKS_TTL_MS = 60 * 60 * 1000;

type AppleJwk = { kid: string; kty: string; alg: string; use: string; n: string; e: string };

let jwksCache: { keys: AppleJwk[]; fetchedAt: number } | undefined;

async function fetchAppleKeys(): Promise<AppleJwk[]> {
  if (jwksCache && Date.now() - jwksCache.fetchedAt < JWKS_TTL_MS) return jwksCache.keys;
  const res = await fetch(APPLE_JWKS_URL);
  if (!res.ok) throw new AppleAuthError(`Apple JWKS fetch failed (${res.status})`);
  const body = (await res.json()) as { keys: AppleJwk[] };
  jwksCache = { keys: body.keys, fetchedAt: Date.now() };
  return body.keys;
}

export class AppleAuthError extends Error {}

export type AppleIdentity = {
  sub: string;
  email?: string;
  emailVerified: boolean;
};

/**
 * Verifies an "Sign in with Apple" identity token: RS256 signature against
 * Apple's published keys, issuer `appleid.apple.com`, audience = our client id.
 */
export async function verifyAppleIdentityToken(
  idToken: string,
  clientId: string,
): Promise<AppleIdentity> {
  const decoded = jwt.decode(idToken, { complete: true });
  if (!decoded || typeof decoded === 'string') throw new AppleAuthError('malformed identity token');

  const kid = decoded.header.kid;
  const jwk = (await fetchAppleKeys()).find((k) => k.kid === kid);
  if (!jwk) throw new AppleAuthError('identity token signed with an unknown key');

  const pem = createPublicKey({ key: jwk as unknown as JsonWebKey, format: 'jwk' }).export({
    format: 'pem',
    type: 'spki',
  }).toString();

  let payload: jwt.JwtPayload | string;
  try {
    payload = jwt.verify(idToken, pem, {
      algorithms: ['RS256'],
      issuer: APPLE_ISSUER,
      audience: clientId,
    });
  } catch (err) {
    throw new AppleAuthError((err as Error).message);
  }

  if (typeof payload === 'string' || !payload.sub) throw new AppleAuthError('identity token missing sub');

  return {
    sub: payload.sub,
    email: typeof payload.email === 'string' ? payload.email : undefined,
    emailVerified: payload.email_verified === true || payload.email_verified === 'true',
  };
}
