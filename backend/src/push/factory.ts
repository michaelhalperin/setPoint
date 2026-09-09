import { env, isProd } from '../env.js';
import { ApnsPushSender } from './apns.js';
import { stubPushSender } from './stub.js';
import type { PushSender } from './types.js';

/**
 * Real APNs sender when all four APNS_* vars are set, otherwise the stub.
 * The private key may carry literal `\n` from the env var; restore real newlines.
 */
export function createPushSender(): PushSender {
  if (env.APNS_KEY_ID && env.APNS_TEAM_ID && env.APNS_PRIVATE_KEY && env.APNS_BUNDLE_ID) {
    return new ApnsPushSender({
      keyId: env.APNS_KEY_ID,
      teamId: env.APNS_TEAM_ID,
      privateKey: env.APNS_PRIVATE_KEY.replace(/\\n/g, '\n'),
      bundleId: env.APNS_BUNDLE_ID,
      production: isProd,
    });
  }

  console.warn('[push] APNs is not configured — using the stub sender');
  return stubPushSender;
}
