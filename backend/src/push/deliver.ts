import type { PrismaClient } from '@prisma/client';
import type { PushPayload, PushSender } from './types.js';

export type DeliveryOutcome = {
  status: 'SENT' | 'FAILED';
  lastPushError: string | null;
  invalidTokens: string[];
};

/**
 * Delivers a check-in as one Time Sensitive alert per device — the single,
 * actionable notification (Log / Snooze). The app starts and ends the Live
 * Activity itself when it loads the check-in; a remote push-to-start would
 * carry its own alert and buzz the user twice. No token, or every send
 * failing, is FAILED — callers must not count that as a miss.
 */
export async function deliverCheckIn(opts: {
  prisma: PrismaClient;
  push: PushSender;
  userId: string;
  payload: PushPayload;
}): Promise<DeliveryOutcome> {
  const tokens = await opts.prisma.pushToken.findMany({ where: { userId: opts.userId, kind: 'alert' } });
  const alerts = tokens.map((t) => t.token);
  if (alerts.length === 0) {
    return { status: 'FAILED', lastPushError: 'no_push_token', invalidTokens: [] };
  }

  const result = await opts.push.send(alerts, opts.payload);

  if (result.invalidTokens.length > 0) {
    await opts.prisma.pushToken.deleteMany({ where: { token: { in: result.invalidTokens } } });
  }

  if (result.sent === 0) {
    return { status: 'FAILED', lastPushError: result.error ?? 'apns_failed', invalidTokens: result.invalidTokens };
  }
  return { status: 'SENT', lastPushError: null, invalidTokens: result.invalidTokens };
}
