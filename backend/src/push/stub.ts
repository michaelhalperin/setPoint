import type { PushSender } from './types.js';

/** No-op sender used until the APNs auth key is configured. */
export const stubPushSender: PushSender = {
  async send(deviceTokens, payload) {
    console.info(
      `[push:stub] tier ${payload.tier} → ${deviceTokens.length} alert(s) · checkIn=${payload.checkInId} · "${payload.body}"`,
    );
    return { attempted: deviceTokens.length, sent: deviceTokens.length, failed: 0, invalidTokens: [] };
  },
};
