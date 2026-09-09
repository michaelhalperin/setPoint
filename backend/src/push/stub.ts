import type { PushSender } from './types.js';

/** No-op sender used until the APNs auth key is configured. */
export const stubPushSender: PushSender = {
  async send(deviceTokens, payload) {
    console.info(
      `[push:stub] tier ${payload.tier} → ${deviceTokens.length} device(s) · ` +
        `checkIn=${payload.checkInId} · "${payload.body}"`,
    );
  },
};
