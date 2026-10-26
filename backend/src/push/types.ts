export type PushPayload = {
  userId: string;
  checkInId: string;
  tier: number;
  title: string;
  body: string;
  /** The suggested meal, so "I ate this" works straight from the notification. */
  prescriptionId?: string | null;
  category?: 'CHECK_IN' | 'HEADS_UP' | 'REFUEL';
  /** Admin test only: a bare alert with no Time Sensitive level and no action buttons. */
  plain?: boolean;
};

export type PushSendResult = {
  attempted: number;
  sent: number;
  failed: number;
  invalidTokens: string[];
  error?: string;
};

/**
 * Delivers a check-in to a user's devices. The real implementation (APNs Live
 * Activity + `interruptionLevel: .timeSensitive`, plan §2) lands once the APNs
 * auth key exists; until then `stubPushSender` just logs.
 */
export interface PushSender {
  send(deviceTokens: string[], payload: PushPayload): Promise<PushSendResult>;
}
