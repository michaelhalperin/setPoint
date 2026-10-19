import { describe, expect, it, vi } from 'vitest';

vi.hoisted(() => {
  process.env.JWT_SECRET ||= 'test-jwt-secret';
  process.env.CRON_SECRET ||= 'test-cron-secret';
});

const findUnique = vi.hoisted(() => vi.fn());
vi.mock('../db/client.js', () => ({ getPrisma: () => ({ user: { findUnique } }) }));

import sensible from '@fastify/sensible';
import Fastify from 'fastify';
import jwt from 'jsonwebtoken';
import { env } from '../env.js';
import { requireAuth } from './index.js';
import {
  RENEW_AFTER_SECONDS,
  SESSION_RENEWAL_HEADER,
  issueSessionToken,
  shouldRenewSession,
  verifySessionToken,
} from './session.js';

const DAY_S = 24 * 60 * 60;

/** A token for u1 as if it had been issued `ageSeconds` ago. */
function tokenIssuedAgo(ageSeconds: number): string {
  const iat = Math.floor(Date.now() / 1000) - ageSeconds;
  return jwt.sign({ sub: 'u1', iat, exp: iat + 60 * DAY_S }, env.JWT_SECRET, { algorithm: 'HS256' });
}

describe('session tokens', () => {
  it('round-trips the user id and issue time', () => {
    const { userId, issuedAt } = verifySessionToken(issueSessionToken('u1'));
    expect(userId).toBe('u1');
    expect(Math.abs(Date.now() - issuedAt!.getTime())).toBeLessThan(5_000);
  });

  it('renews only once a token is a week old', () => {
    const now = new Date('2026-09-10T12:00:00Z');
    const ago = (s: number) => new Date(now.getTime() - s * 1000);
    expect(shouldRenewSession(ago(DAY_S), now)).toBe(false);
    expect(shouldRenewSession(ago(RENEW_AFTER_SECONDS - 1), now)).toBe(false);
    expect(shouldRenewSession(ago(RENEW_AFTER_SECONDS), now)).toBe(true);
    expect(shouldRenewSession(null, now)).toBe(true);
  });
});

describe('requireAuth', () => {
  async function app() {
    const server = Fastify();
    await server.register(sensible);
    server.get('/me', { preHandler: requireAuth(server) }, async () => ({ ok: true }));
    return server;
  }

  it('hands back a fresh token when the current one is over a week old', async () => {
    const server = await app();
    const res = await server.inject({
      url: '/me',
      headers: { authorization: `Bearer ${tokenIssuedAgo(8 * DAY_S)}` },
    });
    expect(res.statusCode).toBe(200);
    const renewed = res.headers[SESSION_RENEWAL_HEADER];
    expect(typeof renewed).toBe('string');
    const verified = verifySessionToken(renewed as string);
    expect(verified.userId).toBe('u1');
    expect(shouldRenewSession(verified.issuedAt)).toBe(false);
  });

  it('leaves a recent token alone', async () => {
    const server = await app();
    const res = await server.inject({
      url: '/me',
      headers: { authorization: `Bearer ${tokenIssuedAgo(DAY_S)}` },
    });
    expect(res.statusCode).toBe(200);
    expect(res.headers[SESSION_RENEWAL_HEADER]).toBeUndefined();
  });

  it('still rejects an invalid token', async () => {
    const server = await app();
    const res = await server.inject({ url: '/me', headers: { authorization: 'Bearer nope' } });
    expect(res.statusCode).toBe(401);
    expect(res.headers[SESSION_RENEWAL_HEADER]).toBeUndefined();
  });
});

describe('invite-only sessions', () => {
  async function app() {
    const server = Fastify();
    await server.register(sensible);
    server.get('/me', { preHandler: requireAuth(server) }, async () => ({ ok: true }));
    server.post('/invite', { preHandler: requireAuth(server, { allowPendingInvite: true }) }, async () => ({ ok: true }));
    return server;
  }
  const pending = () => issueSessionToken('u1', { pendingInvite: true });
  const withInviteOnly = async (on: boolean, run: () => Promise<void>) => {
    const before = env.INVITE_ONLY;
    env.INVITE_ONLY = on ? 'true' : '';
    try {
      await run();
    } finally {
      env.INVITE_ONLY = before;
      findUnique.mockReset();
    }
  };

  it('marks pending tokens, and only those', () => {
    expect(verifySessionToken(pending()).pendingInvite).toBe(true);
    expect(verifySessionToken(issueSessionToken('u1')).pendingInvite).toBe(false);
  });

  it('turns a pending account away with invite_required', () =>
    withInviteOnly(true, async () => {
      findUnique.mockResolvedValue({ accessGrantedAt: null });
      const res = await (await app()).inject({ url: '/me', headers: { authorization: `Bearer ${pending()}` } });
      expect(res.statusCode).toBe(403);
      expect(res.json().message).toBe('invite_required');
    }));

  it('lets a pending account redeem a code', () =>
    withInviteOnly(true, async () => {
      findUnique.mockResolvedValue({ accessGrantedAt: null });
      const res = await (await app()).inject({ method: 'POST', url: '/invite', headers: { authorization: `Bearer ${pending()}` } });
      expect(res.statusCode).toBe(200);
    }));

  it('upgrades a pending session once an admin has let the account in', () =>
    withInviteOnly(true, async () => {
      findUnique.mockResolvedValue({ accessGrantedAt: new Date() });
      const res = await (await app()).inject({ url: '/me', headers: { authorization: `Bearer ${pending()}` } });
      expect(res.statusCode).toBe(200);
      expect(verifySessionToken(res.headers[SESSION_RENEWAL_HEADER] as string).pendingInvite).toBe(false);
    }));

  it('never reads the database for a full session', () =>
    withInviteOnly(true, async () => {
      const res = await (await app()).inject({ url: '/me', headers: { authorization: `Bearer ${tokenIssuedAgo(DAY_S)}` } });
      expect(res.statusCode).toBe(200);
      expect(findUnique).not.toHaveBeenCalled();
    }));

  it('lets pending tokens through, upgraded, once invites are switched off', () =>
    withInviteOnly(false, async () => {
      const res = await (await app()).inject({ url: '/me', headers: { authorization: `Bearer ${pending()}` } });
      expect(res.statusCode).toBe(200);
      expect(verifySessionToken(res.headers[SESSION_RENEWAL_HEADER] as string).pendingInvite).toBe(false);
    }));
});
