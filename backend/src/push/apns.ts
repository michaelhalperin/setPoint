import http2 from 'node:http2';
import jwt from 'jsonwebtoken';
import type { PushPayload, PushSender } from './types.js';

export type ApnsConfig = {
  keyId: string;
  teamId: string;
  /** Contents of the APNs auth key (.p8) — a PEM private key. */
  privateKey: string;
  /** App bundle id, e.g. com.setpoint.app. */
  bundleId: string;
  /** true → api.push.apple.com, false → sandbox. */
  production: boolean;
};

type SendOptions = {
  payload: unknown;
  pushType: 'alert' | 'liveactivity' | 'background';
  topic: string;
  priority?: 5 | 10;
  expiration?: number;
  collapseId?: string;
};

export type ApnsSendResult = {
  deviceToken: string;
  ok: boolean;
  status: number;
  reason?: string;
};

const APNS_HOSTS = {
  production: 'https://api.push.apple.com',
  sandbox: 'https://api.sandbox.push.apple.com',
};

/** Minimal token-authenticated APNs client over HTTP/2 (no third-party dep). */
export class ApnsClient {
  private session?: http2.ClientHttp2Session;
  private cachedToken?: { value: string; issuedAt: number };

  constructor(private readonly config: ApnsConfig) {}

  private host(): string {
    return this.config.production ? APNS_HOSTS.production : APNS_HOSTS.sandbox;
  }

  /** APNs allows a provider token to be reused for up to 1h; refresh at ~50m. */
  private authToken(): string {
    const now = Math.floor(Date.now() / 1000);
    if (this.cachedToken && now - this.cachedToken.issuedAt < 3000) {
      return this.cachedToken.value;
    }
    const value = jwt.sign({ iss: this.config.teamId, iat: now }, this.config.privateKey, {
      algorithm: 'ES256',
      keyid: this.config.keyId,
    });
    this.cachedToken = { value, issuedAt: now };
    return value;
  }

  private getSession(): http2.ClientHttp2Session {
    if (!this.session || this.session.closed || this.session.destroyed) {
      this.session = http2.connect(this.host());
      this.session.on('error', () => {
        this.session = undefined;
      });
    }
    return this.session;
  }

  send(deviceToken: string, options: SendOptions): Promise<ApnsSendResult> {
    const session = this.getSession();
    const headers: Record<string, string> = {
      ':method': 'POST',
      ':path': `/3/device/${deviceToken}`,
      authorization: `bearer ${this.authToken()}`,
      'apns-topic': options.topic,
      'apns-push-type': options.pushType,
      'apns-priority': String(options.priority ?? 10),
    };
    if (options.expiration != null) headers['apns-expiration'] = String(options.expiration);
    if (options.collapseId) headers['apns-collapse-id'] = options.collapseId;

    return new Promise<ApnsSendResult>((resolve, reject) => {
      const req = session.request(headers);
      let status = 0;
      let body = '';

      req.on('response', (h) => {
        status = Number(h[':status'] ?? 0);
      });
      req.setEncoding('utf8');
      req.on('data', (chunk) => {
        body += chunk;
      });
      req.on('error', reject);
      req.on('end', () => {
        const ok = status === 200;
        let reason: string | undefined;
        if (!ok && body) {
          try {
            reason = (JSON.parse(body) as { reason?: string }).reason;
          } catch {
            reason = body.slice(0, 200);
          }
        }
        resolve({ deviceToken, ok, status, reason });
      });

      req.end(JSON.stringify(options.payload));
    });
  }

  close(): void {
    this.session?.close();
    this.session = undefined;
  }
}

/**
 * Builds the aps payload for a check-in — a Time Sensitive alert that
 * deep-links into the full-screen prescription view (plan §2, §5a). Pure.
 */
export function buildCheckInAlertPayload(payload: PushPayload): Record<string, unknown> {
  return {
    aps: {
      alert: { title: payload.title, body: payload.body },
      sound: 'default',
      'interruption-level': 'time-sensitive',
      'relevance-score': 1,
    },
    checkInId: payload.checkInId,
    tier: payload.tier,
    deepLink: `setpoint://check-in/${payload.checkInId}`,
  };
}

export type LiveActivityState = {
  title: string;
  detail: string;
  deepLink: string;
};

/**
 * Builds the `aps` payload for a Live Activity push (plan §2). `start` pushes a
 * push-to-start token (iOS 17.2+); `update` / `end` push a per-activity token.
 * Pure.
 */
export function buildLiveActivityPayload(
  event: 'start' | 'update' | 'end',
  state: LiveActivityState,
  options: { checkInId: string; staleAfterSeconds?: number } = { checkInId: '' },
): Record<string, unknown> {
  const now = Math.floor(Date.now() / 1000);
  const aps: Record<string, unknown> = {
    timestamp: now,
    event,
    'content-state': state,
  };
  if (options.staleAfterSeconds) aps['stale-date'] = now + options.staleAfterSeconds;
  if (event === 'start') {
    aps['attributes-type'] = 'CheckInActivityAttributes';
    aps.attributes = { checkInId: options.checkInId };
    aps.alert = { title: state.title, body: state.detail };
  }
  return { aps };
}

/** PushSender backed by real APNs. Failures per-device are logged, not thrown. */
export class ApnsPushSender implements PushSender {
  private readonly client: ApnsClient;

  constructor(private readonly config: ApnsConfig) {
    this.client = new ApnsClient(config);
  }

  async send(deviceTokens: string[], payload: PushPayload): Promise<void> {
    if (deviceTokens.length === 0) return;

    const apnsPayload = buildCheckInAlertPayload(payload);
    const expiration = Math.floor(Date.now() / 1000) + 3600;

    const results = await Promise.allSettled(
      deviceTokens.map((token) =>
        this.client.send(token, {
          payload: apnsPayload,
          pushType: 'alert',
          topic: this.config.bundleId,
          priority: 10,
          expiration,
          collapseId: payload.checkInId,
        }),
      ),
    );

    for (const result of results) {
      if (result.status === 'rejected') {
        console.error('[apns] request failed', result.reason);
      } else if (!result.value.ok) {
        // 410 = the device token is no longer valid; the caller should prune it.
        console.warn(
          `[apns] ${result.value.status} ${result.value.reason ?? ''} for ${result.value.deviceToken.slice(0, 8)}…`,
        );
      }
    }
  }
}
