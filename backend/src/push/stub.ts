import { isProd } from '../env.js';
import type { PushSender } from './types.js';

/**
 * No-op sender used until the APNs auth key is configured. Outside production it
 * pretends to deliver (dev and tests); in production it must not, or a missing
 * key looks like a working push.
 */
export const stubPushSender: PushSender = {
  async send(deviceTokens, payload) {
    console.info(
      `[push:stub] tier ${payload.tier} → ${deviceTokens.length} alert(s) · checkIn=${payload.checkInId} · "${payload.body}"`,
    );
    if (isProd) {
      return { attempted: deviceTokens.length, sent: 0, failed: deviceTokens.length, invalidTokens: [], error: 'apns_not_configured' };
    }
    return { attempted: deviceTokens.length, sent: deviceTokens.length, failed: 0, invalidTokens: [] };
  },
};
