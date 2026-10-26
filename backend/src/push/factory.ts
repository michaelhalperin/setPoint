import { env, isProd } from '../env.js';
import { ApnsPushSender } from './apns.js';
import { stubPushSender } from './stub.js';
import type { PushSender } from './types.js';

/**
 * The .p8 key as a clean PEM, whatever a dashboard did to it: wrapped in quotes,
 * literal `\n` for newlines, newlines turned into spaces, or all on one line.
 */
export function normalizePrivateKey(raw: string): string {
  const body = raw
    .replace(/\\n/g, '\n')
    .replace(/-----(BEGIN|END)[A-Z ]*-----/g, '')
    .replace(/[^A-Za-z0-9+/=]/g, '');
  const lines = body.match(/.{1,64}/g) ?? [];
  return `-----BEGIN PRIVATE KEY-----\n${lines.join('\n')}\n-----END PRIVATE KEY-----\n`;
}

/**
 * Real APNs sender when all four APNS_* vars are set, otherwise the stub.
 * The private key may carry literal `\n` from the env var; restore real newlines.
 */
export function createPushSender(): PushSender {
  if (env.APNS_KEY_ID && env.APNS_TEAM_ID && env.APNS_PRIVATE_KEY && env.APNS_BUNDLE_ID) {
    return new ApnsPushSender({
      keyId: env.APNS_KEY_ID,
      teamId: env.APNS_TEAM_ID,
      privateKey: normalizePrivateKey(env.APNS_PRIVATE_KEY),
      bundleId: env.APNS_BUNDLE_ID,
      production: isProd,
    });
  }

  console.warn('[push] APNs is not configured — using the stub sender');
  return stubPushSender;
}
